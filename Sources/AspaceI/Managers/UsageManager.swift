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

    /// 使用者會定期刪對話紀錄，要趁檔案還在時讀進用量歷史，所以 popup 沒打開也要定時掃。
    func startAutomaticRefresh(instances: InstanceManager) {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(instances: instances)
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
    }

    func refresh(instances: InstanceManager) async {
        guard !isScanning else {
            scanQueued = true
            return
        }
        isScanning = true
        defer { isScanning = false }
        repeat {
            scanQueued = false
            do {
                records = try await service.scan(Self.context(instances: instances))
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
    private static func context(instances: InstanceManager) throws -> UsageScanContext {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        let support = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return UsageScanContext(
            claudeProjectRoots: [home.appending(path: ".claude/projects"), home.appending(path: ".config/claude/projects")],
            codexHomes: [home.appending(path: ".codex")]
                + instances.instances.filter { $0.platform == .codex }.map { URL(fileURLWithPath: $0.profileDirectory) },
            storeDirectory: support.appending(path: "AspaceI", directoryHint: .isDirectory)
        )
    }
}
