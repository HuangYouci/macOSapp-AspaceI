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

    func add(name: String, platform: PlatformKind, executablePath: String) {
        let id = UUID()
        let root = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/AspaceI/Instances/\(id.uuidString)")
        instances.append(Instance(id: id, name: name, platform: platform, profileDirectory: root.path, executablePath: executablePath))
        persist()
    }

    func launch(_ instance: Instance) {
        do { try service.launch(instance) } catch { errorMessage = error.localizedDescription }
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
