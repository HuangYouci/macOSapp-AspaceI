import Foundation
import Observation

/// 本機用量統計。掃描在背景跑，結果與快取都在 `UsageScanService`。
@MainActor
@Observable
final class UsageManager {
    static let refreshInterval: Duration = .seconds(300)

    private(set) var records: [UsageRecord] = []
    private(set) var isScanning = false
    private(set) var hasScanned = false
    private(set) var scannedAt: Date?
    var errorMessage: String?

    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var scanQueued = false
    private let service = UsageScanService.shared

    /// 對話的帳號只能趁它還在桌面 App 的清單裡記下來，所以 popup 沒打開也要定時掃。
    func startAutomaticRefresh(accounts: AccountManager, instances: InstanceManager) {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(accounts: accounts, instances: instances)
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
    }

    func refresh(accounts: AccountManager, instances: InstanceManager) async {
        guard !isScanning else {
            scanQueued = true
            return
        }
        isScanning = true
        defer { isScanning = false }
        repeat {
            scanQueued = false
            do {
                records = try await service.scan(Self.context(accounts: accounts, instances: instances))
                scannedAt = Date()
                errorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
            hasScanned = true
        } while scanQueued
    }

    /// 所有 Claude 桌面實例共用 `~/.claude`；Codex 實例以 `CODEX_HOME` 指到各自的資料夾。
    private static func context(accounts: AccountManager, instances: InstanceManager) throws -> UsageScanContext {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        let support = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let claudeInstances = instances.instances.filter { $0.platform == .claude }
        let codexInstances = instances.instances.filter { $0.platform == .codex }
        return UsageScanContext(
            claudeProjectRoots: [home.appending(path: ".claude/projects"), home.appending(path: ".config/claude/projects")],
            claudeSessionIndexRoots: [support.appending(path: "Claude/claude-code-sessions")]
                + claudeInstances.map { URL(fileURLWithPath: $0.profileDirectory).appending(path: "claude-code-sessions") },
            codexHomes: [.init(url: home.appending(path: ".codex"), accountID: accounts.defaultClientAccount(for: .codex)?.id)]
                + codexInstances.map { .init(url: URL(fileURLWithPath: $0.profileDirectory), accountID: $0.accountID) },
            storeDirectory: support.appending(path: "AspaceI", directoryHint: .isDirectory)
        )
    }
}
