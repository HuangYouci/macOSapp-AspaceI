import AppKit
import Foundation
import Observation
import os

@MainActor
@Observable
final class InstanceManager {
    struct Group: Identifiable {
        let platform: PlatformKind
        let defaultInstance: Instance
        let instances: [Instance]
        let isInstalled: Bool

        var id: PlatformKind { platform }
        var all: [Instance] { [defaultInstance] + instances }
    }

    static let groupOrder: [PlatformKind] = [.githubCopilot, .antigravity, .claude, .codex]

    private(set) var instances: [Instance] = []
    private(set) var switchingPlatform: PlatformKind?
    /// 需要一起更新的平台：有更新程式在等，或有執行中的實例不是同平台最新版。
    private(set) var pendingUpdatePlatforms: Set<PlatformKind> = []
    private(set) var updatingPlatform: PlatformKind?
    private(set) var removingInstanceIDs: Set<UUID> = []
    private(set) var runningProcessIDs: [UUID: [Int32]] = [:]
    /// 實例 id → 該實例的 App 目前登入的平台帳號編號（目前只有 Claude）。
    private(set) var signedInAccountUUIDs: [UUID: String] = [:]
    var errorMessage: String?

    private let service = InstanceService.shared
    private let locator = ExecutableLocatorService.shared
    private let clones = AppCloneService.shared
    private let logger = Logger(subsystem: "com.huangyouci.AspaceI", category: "Instances")
    @ObservationIgnored private weak var monitoredAccounts: AccountManager?
    @ObservationIgnored private var launchObserver: NSObjectProtocol?

    init() {
        do {
            let store = try service.load()
            instances = store.instances
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var groups: [Group] {
        Self.groupOrder.map { platform in
            let appPath = locator.locate(platform)
            return Group(
                platform: platform,
                defaultInstance: Self.defaultInstance(for: platform, appPath: appPath ?? ""),
                instances: instances.filter { $0.platform == platform },
                isInstalled: appPath != nil
            )
        }
    }

    /// 預設實例不存檔，代表系統原本的 App 設定；id 依平台固定，才能追蹤執行狀態。
    static func defaultInstance(for platform: PlatformKind, appPath: String) -> Instance {
        Instance(
            id: defaultID(for: platform),
            name: String(localized: "DefaultInstance", defaultValue: "預設"),
            platform: platform,
            profileDirectory: "",
            executablePath: appPath
        )
    }

    static func defaultID(for platform: PlatformKind) -> UUID {
        let suffix = String(format: "%012x", PlatformKind.allCases.firstIndex(of: platform) ?? 0)
        return UUID(uuidString: "A5AACE10-0000-4000-8000-\(suffix)") ?? UUID()
    }

    func isDefault(_ instance: Instance) -> Bool {
        instance.id == Self.defaultID(for: instance.platform)
    }

    func add(name: String, platform: PlatformKind, accountID: UUID?) {
        do {
            let id = UUID()
            guard let appPath = locator.locate(platform) else { throw InstanceError.executableMissing }
            instances.append(Instance(
                id: id,
                name: name,
                platform: platform,
                accountID: platform.supportsAccountBinding(isDefault: false) ? accountID : nil,
                profileDirectory: try service.profileDirectory(for: id),
                executablePath: appPath
            ))
            persist()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func bind(_ instance: Instance, accountID: UUID?) {
        guard !isDefault(instance), let index = instances.firstIndex(where: { $0.id == instance.id }) else { return }
        instances[index].accountID = accountID
        persist()
    }

    /// 官方 App 是否正在執行，以及它在 Finder 裡的名字（例如 Codex 現在是 ChatGPT.app）。
    func runningDefaultAppName(for platform: PlatformKind) async -> String? {
        guard let appPath = locator.locate(platform) else { return nil }
        let instance = Self.defaultInstance(for: platform, appPath: appPath)
        let pids = InstanceService.mainProcessIDs(for: instance, isDefault: true, in: await processList())
        return pids.isEmpty ? nil : URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
    }

    /// 切換預設實例的帳號：先關閉正在執行的官方 App，寫入新帳號，再重新開啟。
    func switchDefault(to account: Account, accounts: AccountManager) async {
        guard switchingPlatform == nil else { return }
        switchingPlatform = account.platform
        defer { switchingPlatform = nil }
        let instance = Self.defaultInstance(for: account.platform, appPath: locator.locate(account.platform) ?? "")
        do {
            if !instance.executablePath.isEmpty {
                try await quit(instance)
            }
            try await accounts.switchDefaultClient(to: account)
            if !instance.executablePath.isEmpty {
                try service.launch(instance, appPath: instance.executablePath, isDefault: true)
                scheduleRunningRefresh()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func quit(_ instance: Instance, timeoutError: InstanceError = .quitTimedOut) async throws {
        try await quit([instance], timeoutError: timeoutError)
    }

    /// 一次送出 SIGTERM，再等全部主程序結束（最多 10 秒）。
    private func quit(_ targets: [Instance], timeoutError: InstanceError) async throws {
        func pids(in processes: [Int32: String]) -> [Int32] {
            targets.flatMap { InstanceService.mainProcessIDs(for: $0, isDefault: isDefault($0), in: processes) }
        }
        let initial = pids(in: await processList())
        guard !initial.isEmpty else { return }
        service.stop(processIDs: initial)
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(500))
            if pids(in: await processList()).isEmpty {
                for target in targets { runningProcessIDs[target.id] = nil }
                try await Task.sleep(for: .milliseconds(500))
                return
            }
        }
        throw timeoutError
    }

    /// 一起更新：關閉這個 App 的所有實例，等原本的 App 與各複本的更新程式裝完，再把原本開著的實例開回來。
    /// 開回來時複本一律換成同平台版本最新的那份，所以不論是哪一份先拿到更新，全部會對齊到同一版。
    /// 原本的 App 只有預設實例自己的更新程式能換，複本較新時預設實例會晚一步。
    func updateAndRelaunch(_ platform: PlatformKind, accounts: AccountManager) async {
        guard updatingPlatform == nil, let group = groups.first(where: { $0.platform == platform }), group.isInstalled else { return }
        updatingPlatform = platform
        defer { updatingPlatform = nil }
        let appPath = group.defaultInstance.executablePath
        let processes = await processList()
        let running = group.all.filter { !InstanceService.mainProcessIDs(for: $0, isDefault: isDefault($0), in: processes).isEmpty }
        var failure: Error?
        do {
            try await quit(running, timeoutError: .updateQuitTimedOut)
            try await waitForUpdaters(appPath: appPath, cloneFolders: cloneFolders(for: platform))
        } catch {
            failure = error
        }
        // 更新失敗也要把實例開回來；還在跑的（關閉逾時）跳過，免得開出第二個程序。
        let stillRunning = await processList()
        for instance in running where InstanceService.mainProcessIDs(for: instance, isDefault: isDefault(instance), in: stillRunning).isEmpty {
            launch(instance, accounts: accounts)
        }
        if let failure { errorMessage = failure.localizedDescription }
        refreshRunning()
    }

    /// 安裝通常幾秒內完成；等到 60 秒還在就放棄，讓使用者至少拿回實例。
    private func waitForUpdaters(appPath: String, cloneFolders: Set<String>) async throws {
        for _ in 0..<120 {
            if InstanceService.updaterProcessIDs(appPath: appPath, cloneFolders: cloneFolders, in: await processList()).isEmpty { return }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw InstanceError.updateTimedOut
    }

    private func processList() async -> [Int32: String] {
        await Task.detached(priority: .userInitiated) { [service] in service.runningProcessIDs() }.value
    }

    func launch(_ instance: Instance, accounts: AccountManager) {
        let isDefault = isDefault(instance)
        do {
            if !isDefault,
               instance.platform.supportsAccountBinding(isDefault: false),
               let accountID = instance.accountID,
               let account = accounts.accounts.first(where: { $0.id == accountID }) {
                let data = try accounts.credentialData(for: accountID)
                try CredentialProjectionService.shared.project(account: account, credentialData: data, to: URL(fileURLWithPath: instance.profileDirectory))
            }
            var appPath = instance.executablePath
            var cloneError: Error?
            if !isDefault {
                do {
                    appPath = try prepareClone(for: instance, accounts: accounts).path
                } catch {
                    // 複本只影響 Dock 圖示，做不出來就用原本的 App 開，實例照常可用。
                    logger.error("InstanceManager.launch | 準備實例 App 失敗：\(error.localizedDescription, privacy: .public)")
                    cloneError = error
                }
            }
            try service.launch(instance, appPath: appPath, isDefault: isDefault)
            errorMessage = cloneError?.localizedDescription
            scheduleRunningRefresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 複本檔名為「App 名稱 - 使用者名稱」，圖示右下角為與 menu bar 相同的三字短名稱；不知道帳號時用實例名稱。
    private func prepareClone(for instance: Instance, accounts: AccountManager) throws -> URL {
        let account = account(for: instance, accounts: accounts)
        let original = URL(fileURLWithPath: instance.executablePath)
        return try clones.prepare(
            source: newestBundle(for: instance.platform, original: original),
            original: original,
            instance: instance,
            title: "\(original.deletingPathExtension().lastPathComponent) - \(account?.label ?? instance.name)",
            badge: shortLabel(for: instance, account: account, accounts: accounts)
        )
    }

    private func account(for instance: Instance, accounts: AccountManager) -> Account? {
        if instance.platform == .claude {
            guard let uuid = service.claudeSignedInAccountUUID(for: instance, isDefault: false) else { return nil }
            return accounts.accounts.first { $0.platform == .claude && $0.accountUUID == uuid }
        }
        guard let accountID = instance.accountID else { return nil }
        return accounts.accounts.first { $0.id == accountID }
    }

    /// 帳號的短名稱與 menu bar 一樣，只在所有帳號之間比；沒帳號的實例用實例名稱，與帳號和其他這類實例一起比。
    private func shortLabel(for instance: Instance, account: Account?, accounts: AccountManager) -> String {
        let accountLabels = accounts.accounts.map(\.label)
        if let account, let index = accounts.accounts.firstIndex(where: { $0.id == account.id }) {
            return ShortLabel.labels(for: accountLabels)[index]
        }
        let unbound = instances.filter { $0.id == instance.id || self.account(for: $0, accounts: accounts) == nil }
        let labels = ShortLabel.labels(for: accountLabels + unbound.map(\.name))
        guard let index = unbound.firstIndex(where: { $0.id == instance.id }) else { return String(instance.name.prefix(ShortLabel.length)) }
        return labels[accountLabels.count + index]
    }

    private func cloneFolders(for platform: PlatformKind) -> Set<String> {
        Set(instances.filter { $0.platform == platform }.map { AppCloneService.folderName(for: $0.id) })
    }

    /// 原本的 App 與同平台所有複本中版本最新的那份；同版時用原本的 App。
    private func newestBundle(for platform: PlatformKind, original: URL) -> URL {
        var candidates = [(url: original, version: AppCloneService.bundleVersion(of: original))]
        for instance in instances where instance.platform == platform {
            do {
                candidates += try clones.bundles(for: instance.id).map { ($0, AppCloneService.bundleVersion(of: $0)) }
            } catch {
                logger.error("InstanceManager.newestBundle | 讀取 \(instance.name, privacy: .public) 的複本失敗：\(error.localizedDescription, privacy: .public)")
            }
        }
        return AppCloneService.newest(candidates) ?? original
    }

    /// 有更新程式在等，或有執行中的實例比同平台最新版舊（別的複本或原本的 App 已經更新過）。
    private func needsUpdate(_ group: Group, processes: [Int32: String]) -> Bool {
        let appPath = group.defaultInstance.executablePath
        if !InstanceService.updaterProcessIDs(appPath: appPath, cloneFolders: cloneFolders(for: group.platform), in: processes).isEmpty {
            return true
        }
        guard let newest = AppCloneService.bundleVersion(of: newestBundle(for: group.platform, original: URL(fileURLWithPath: appPath))) else { return false }
        return group.all.contains { instance in
            InstanceService.mainProcessIDs(for: instance, isDefault: isDefault(instance), in: processes).contains { pid in
                guard let command = processes[pid], let bundle = InstanceService.bundlePath(fromCommand: command),
                      let version = AppCloneService.bundleVersion(of: URL(fileURLWithPath: bundle)) else { return false }
                return version.compare(newest, options: .numeric) == .orderedAscending
            }
        }
    }

    /// 複本被它自己的更新程式重開時不帶任何參數，開到的是預設資料夾而不是這個實例。
    /// 偵測到就把它關掉，改用實例資料夾重開，順便把被改回原名的複本換回實例名稱與圖示。
    func startMonitoring(accounts: AccountManager) {
        monitoredAccounts = accounts
        guard launchObserver == nil else { return }
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let path = app.bundleURL?.path else { return }
            let pid = app.processIdentifier
            Task { @MainActor in await self?.recoverBareClone(pid: pid, bundlePath: path) }
        }
    }

    private func recoverBareClone(pid: Int32, bundlePath: String) async {
        guard let folder = AppCloneService.instanceFolder(inPath: bundlePath),
              let instance = instances.first(where: { AppCloneService.folderName(for: $0.id) == folder }),
              let accounts = monitoredAccounts else { return }
        let command = await processList()[pid]
        if let command, command.contains("--user-data-dir") { return }
        logger.notice("InstanceManager.recoverBareClone | \(instance.name, privacy: .public) 的複本被不帶參數開啟，改以實例資料夾重開")
        if command != nil {
            service.stop(processIDs: [pid])
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(500))
                if await processList()[pid] == nil { break }
            }
        }
        // 實例已經在跑（例如從 Dock 點了複本）就把它叫到前面，否則看起來像是點了打不開。
        if let running = InstanceService.mainProcessIDs(for: instance, isDefault: false, in: await processList()).first {
            NSRunningApplication(processIdentifier: running)?.activate()
            return
        }
        launch(instance, accounts: accounts)
    }

    func stop(_ instance: Instance) {
        service.stop(processIDs: runningProcessIDs[instance.id] ?? [])
        scheduleRunningRefresh()
    }

    func isRunning(_ instance: Instance) -> Bool {
        !(runningProcessIDs[instance.id] ?? []).isEmpty
    }

    func refreshRunning() {
        let processes = service.runningProcessIDs()
        var result: [UUID: [Int32]] = [:]
        var signedIn: [UUID: String] = [:]
        var pendingUpdates: Set<PlatformKind> = []
        for group in groups {
            if group.isInstalled, needsUpdate(group, processes: processes) {
                pendingUpdates.insert(group.platform)
            }
            for instance in group.all {
                let pids = InstanceService.mainProcessIDs(for: instance, isDefault: isDefault(instance), in: processes)
                if !pids.isEmpty { result[instance.id] = pids }
                signedIn[instance.id] = service.claudeSignedInAccountUUID(for: instance, isDefault: isDefault(instance))
            }
        }
        runningProcessIDs = result
        signedInAccountUUIDs = signedIn
        pendingUpdatePlatforms = pendingUpdates
    }

    /// 先等實例程序真的結束再把資料夾移到垃圾桶，否則還在跑的 App 會把資料夾寫回來。
    func remove(_ instance: Instance) async {
        guard !isDefault(instance), !removingInstanceIDs.contains(instance.id) else { return }
        removingInstanceIDs.insert(instance.id)
        defer { removingInstanceIDs.remove(instance.id) }
        do {
            try await quit(instance, timeoutError: .removeQuitTimedOut)
            try service.trashProfile(for: instance)
            try clones.remove(for: instance.id)
            instances.removeAll { $0.id == instance.id }
            persist()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleRunningRefresh() {
        Task { [weak self] in
            for delay in [1, 3] {
                try? await Task.sleep(for: .seconds(delay))
                self?.refreshRunning()
            }
        }
    }

    private func persist() {
        do {
            try service.save(InstanceStoreFile(instances: instances))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
