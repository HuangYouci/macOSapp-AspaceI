import Foundation
import Observation

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
    private(set) var runningProcessIDs: [UUID: [Int32]] = [:]
    var errorMessage: String?

    private let service = InstanceService.shared
    private let locator = ExecutableLocatorService.shared

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
            try accounts.switchDefaultClient(to: account)
            if !instance.executablePath.isEmpty {
                try service.launch(instance, isDefault: true)
                scheduleRunningRefresh()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func quit(_ instance: Instance) async throws {
        let isDefault = isDefault(instance)
        var pids = InstanceService.mainProcessIDs(for: instance, isDefault: isDefault, in: await processList())
        guard !pids.isEmpty else { return }
        service.stop(processIDs: pids)
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(500))
            pids = InstanceService.mainProcessIDs(for: instance, isDefault: isDefault, in: await processList())
            if pids.isEmpty {
                runningProcessIDs[instance.id] = nil
                try await Task.sleep(for: .milliseconds(500))
                return
            }
        }
        throw InstanceError.quitTimedOut
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
            try service.launch(instance, isDefault: isDefault)
            errorMessage = nil
            scheduleRunningRefresh()
        } catch {
            errorMessage = error.localizedDescription
        }
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
        for group in groups {
            for instance in group.all {
                let pids = InstanceService.mainProcessIDs(for: instance, isDefault: isDefault(instance), in: processes)
                if !pids.isEmpty { result[instance.id] = pids }
            }
        }
        runningProcessIDs = result
    }

    func remove(_ instance: Instance) {
        guard !isDefault(instance) else { return }
        stop(instance)
        do {
            try service.trashProfile(for: instance)
            instances.removeAll { $0.id == instance.id }
            persist()
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
