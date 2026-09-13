import Darwin
import Foundation

struct InstanceStoreFile: Codable, Sendable {
    var instances: [Instance]

    init(instances: [Instance] = []) {
        self.instances = instances
    }
}

final class InstanceService: Sendable {
    static let shared = InstanceService()
    private init() {}

    func load() throws -> InstanceStoreFile {
        let url = try storeURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return InstanceStoreFile() }
        let data = try Data(contentsOf: url)
        if let legacy = try? JSONDecoder().decode([Instance].self, from: data) {
            return InstanceStoreFile(instances: legacy)
        }
        return try JSONDecoder().decode(InstanceStoreFile.self, from: data)
    }

    func save(_ store: InstanceStoreFile) throws {
        try JSONEncoder().encode(store).write(to: try storeURL(), options: [.atomic, .completeFileProtection])
    }

    /// 以 `open` 啟動桌面 App；預設實例沿用系統既有視窗，其他實例強制開新程序並指定獨立資料夾。
    func launch(_ instance: Instance, isDefault: Bool) throws {
        guard FileManager.default.fileExists(atPath: instance.executablePath) else { throw InstanceError.executableMissing }
        if !isDefault {
            try FileManager.default.createDirectory(atPath: instance.profileDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = Self.openArguments(for: instance, isDefault: isDefault)
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw InstanceError.launchFailed }
    }

    static func openArguments(for instance: Instance, isDefault: Bool) -> [String] {
        guard !isDefault else { return ["-a", instance.executablePath] + (instance.arguments.isEmpty ? [] : ["--args"] + instance.arguments) }
        let profile = instance.profileDirectory
        var arguments = ["-n"]
        var appArguments: [String]
        switch instance.platform {
        case .codex:
            arguments += ["--env", "CODEX_HOME=\(profile)"]
            appArguments = ["--user-data-dir", "\(profile)/app-data"]
        case .claude:
            arguments += ["--env", "CLAUDE_USER_DATA_DIR=\(profile)"]
            appArguments = ["--user-data-dir", profile]
        case .antigravity, .githubCopilot:
            appArguments = ["--user-data-dir", profile]
        }
        appArguments += instance.arguments
        return arguments + ["-a", instance.executablePath, "--args"] + appArguments
    }

    func runningProcessIDs() -> [Int32: String] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axww", "-o", "pid=,command="]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return [:]
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Self.parseProcessList(String(decoding: data, as: UTF8.self))
    }

    static func parseProcessList(_ text: String) -> [Int32: String] {
        var result: [Int32: String] = [:]
        for line in text.split(separator: "\n") {
            let trimmed = line.drop { $0 == " " }
            guard let space = trimmed.firstIndex(of: " "), let pid = Int32(trimmed[..<space]) else { continue }
            result[pid] = String(trimmed[trimmed.index(after: space)...])
        }
        return result
    }

    /// 找出屬於該實例的主程序：主執行檔在 App 的 Contents/MacOS 下，並以 user-data-dir 區分實例。
    static func mainProcessIDs(for instance: Instance, isDefault: Bool, in processes: [Int32: String]) -> [Int32] {
        let executablePrefix = "\(instance.executablePath)/Contents/MacOS/"
        let marker = "--user-data-dir \(instance.platform == .codex ? "\(instance.profileDirectory)/app-data" : instance.profileDirectory)"
        return processes.compactMap { pid, command in
            guard command.hasPrefix(executablePrefix) else { return nil }
            let hasUserDataDir = command.contains("--user-data-dir")
            if isDefault { return hasUserDataDir ? nil : pid }
            return command.contains(marker) ? pid : nil
        }
        .sorted()
    }

    func stop(processIDs: [Int32]) {
        for pid in processIDs {
            kill(pid, SIGTERM)
        }
    }

    func trashProfile(for instance: Instance) throws {
        let profile = URL(fileURLWithPath: instance.profileDirectory).standardizedFileURL
        let base = try instancesRootURL().standardizedFileURL
        guard profile.deletingLastPathComponent() == base else { throw InstanceError.unsafeProfilePath }
        guard FileManager.default.fileExists(atPath: profile.path) else { return }
        var result: NSURL?
        try FileManager.default.trashItem(at: profile, resultingItemURL: &result)
    }

    func profileDirectory(for id: UUID) throws -> String {
        try instancesRootURL().appending(path: id.uuidString, directoryHint: .isDirectory).path
    }

    private func storeURL() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appending(path: "AspaceI", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return directory.appending(path: "instances.json")
    }

    private func instancesRootURL() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appending(path: "AspaceI/Instances", directoryHint: .isDirectory)
    }
}

enum InstanceError: LocalizedError {
    case executableMissing, unsafeProfilePath, launchFailed, quitTimedOut
    var errorDescription: String? {
        switch self {
        case .executableMissing: "找不到 App"
        case .unsafeProfilePath: "拒絕刪除不在 AspaceI 管理範圍內的資料夾"
        case .launchFailed: "App 啟動失敗"
        case .quitTimedOut: "App 沒有在時間內關閉，未切換帳號"
        }
    }
}
