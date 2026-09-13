import Foundation

final class InstanceService: @unchecked Sendable {
    static let shared = InstanceService()
    private let lock = NSLock()
    private var processes: [UUID: Process] = [:]
    private init() {}

    func load() throws -> [Instance] {
        let url = try storeURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([Instance].self, from: Data(contentsOf: url))
    }

    func save(_ instances: [Instance]) throws {
        try JSONEncoder().encode(instances).write(to: try storeURL(), options: [.atomic, .completeFileProtection])
    }

    func launch(_ instance: Instance) throws {
        guard FileManager.default.isExecutableFile(atPath: instance.executablePath) else { throw InstanceError.executableMissing }
        try FileManager.default.createDirectory(atPath: instance.profileDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let process = Process()
        process.executableURL = URL(fileURLWithPath: instance.executablePath)
        process.arguments = launchArguments(for: instance)
        var environment = ProcessInfo.processInfo.environment
        if instance.platform == .codex { environment["CODEX_HOME"] = instance.profileDirectory }
        if instance.platform == .claude { environment["CLAUDE_CONFIG_DIR"] = instance.profileDirectory }
        process.environment = environment
        process.terminationHandler = { [weak self] _ in self?.removeProcess(id: instance.id) }
        try process.run()
        lock.withLock { processes[instance.id] = process }
    }

    func stop(id: UUID) {
        let process = lock.withLock { processes[id] }
        process?.terminate()
    }

    func isRunning(id: UUID) -> Bool { lock.withLock { processes[id]?.isRunning == true } }

    private func launchArguments(for instance: Instance) -> [String] {
        switch instance.platform {
        case .antigravity, .githubCopilot: ["--user-data-dir", instance.profileDirectory] + instance.arguments
        case .codex, .claude: instance.arguments
        }
    }

    private func removeProcess(id: UUID) { lock.withLock { processes[id] = nil } }

    private func storeURL() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appending(path: "AspaceI", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return directory.appending(path: "instances.json")
    }
}

enum InstanceError: LocalizedError {
    case executableMissing
    var errorDescription: String? { "找不到可執行檔" }
}
