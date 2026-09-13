import Foundation
import Observation

@MainActor
@Observable
final class InstanceManager {
    private(set) var instances: [Instance] = []
    var errorMessage: String?
    private let service = InstanceService.shared

    init() {
        do { instances = try service.load() } catch { errorMessage = error.localizedDescription }
    }

    func add(name: String, platform: PlatformKind, accountID: UUID?, executablePath: String) {
        let id = UUID()
        let root = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/AspaceI/Instances/\(id.uuidString)")
        instances.append(Instance(id: id, name: name, platform: platform, accountID: accountID, profileDirectory: root.path, executablePath: executablePath))
        persist()
    }

    func launch(_ instance: Instance, accounts: AccountManager) {
        do {
            if let accountID = instance.accountID, let account = accounts.accounts.first(where: { $0.id == accountID }) {
                let data = try accounts.credentialData(for: accountID)
                try CredentialProjectionService.shared.project(account: account, credentialData: data, to: URL(fileURLWithPath: instance.profileDirectory))
            }
            try service.launch(instance)
        } catch { errorMessage = error.localizedDescription }
    }

    func stop(_ instance: Instance) { service.stop(id: instance.id) }
    func isRunning(_ instance: Instance) -> Bool { service.isRunning(id: instance.id) }

    func remove(_ instance: Instance) {
        stop(instance)
        instances.removeAll { $0.id == instance.id }
        persist()
    }

    private func persist() {
        do { try service.save(instances) } catch { errorMessage = error.localizedDescription }
    }
}
