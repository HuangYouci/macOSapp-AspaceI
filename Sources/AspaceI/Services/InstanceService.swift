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

    /// 以 `open -n` 啟動桌面 App；其他實例另外指定獨立資料夾。只在實例沒有執行時呼叫。
    /// `appPath` 是這次要開的 App：預設實例為原本的 App，其他實例為 `AppCloneService` 的複本。
    func launch(_ instance: Instance, appPath: String, isDefault: Bool) throws {
        guard FileManager.default.fileExists(atPath: appPath) else { throw InstanceError.executableMissing }
        if !isDefault {
            try FileManager.default.createDirectory(atPath: instance.profileDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = Self.openArguments(for: instance, appPath: appPath, isDefault: isDefault)
        // open 會把自己的環境變數轉交給 App；DYLD_* 會讓 VS Code 啟動即結束。
        process.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("DYLD_") }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw InstanceError.launchFailed }
    }

    static func openArguments(for instance: Instance, appPath: String, isDefault: Bool) -> [String] {
        // 預設實例也要 -n：同一個 App 已有其他實例在跑時，沒有 -n 的 open 只會把其中一個叫到前面，預設實例根本沒開。
        guard !isDefault else { return ["-n", "-a", appPath] + (instance.arguments.isEmpty ? [] : ["--args"] + instance.arguments) }
        let userDataDirectory = userDataDirectory(for: instance)
        var arguments = ["-n"]
        if instance.platform == .codex {
            // 新版 ChatGPT.app 只認這個環境變數決定資料夾；沒設的話第二個程序會被單一實例鎖直接結束。
            arguments += ["--env", "CODEX_HOME=\(instance.profileDirectory)", "--env", "CODEX_ELECTRON_USER_DATA_PATH=\(userDataDirectory)"]
        }
        // 必須用等號形式：Claude 會忽略空格分開的寫法，改用預設資料夾。
        let appArguments = ["--user-data-dir=\(userDataDirectory)"] + instance.arguments
        return arguments + ["-a", appPath, "--args"] + appArguments
    }

    static func userDataDirectory(for instance: Instance) -> String {
        instance.platform == .codex ? "\(instance.profileDirectory)/app-data" : instance.profileDirectory
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

    /// 找出屬於該實例的主程序。預設實例：原本 App 的主執行檔、沒有 user-data-dir、不在複本資料夾。
    /// 只比對 App 名稱而非完整路徑，因為隔離中的 App 會從 AppTranslocation 的暫存路徑執行。
    /// 其他實例：任何 App 的主執行檔（原本的或複本，複本檔名會變）且 user-data-dir 相符。
    static func mainProcessIDs(for instance: Instance, isDefault: Bool, in processes: [Int32: String]) -> [Int32] {
        let executableMarker = originalExecutableMarker(appPath: instance.executablePath)
        let directory = userDataDirectory(for: instance)
        return processes.compactMap { pid, command in
            let hasUserDataDir = command.contains("--user-data-dir")
            if isDefault {
                return command.contains(executableMarker) && isMainExecutable(command) && !hasUserDataDir && !AppCloneService.isClonePath(command) ? pid : nil
            }
            guard isMainExecutable(command) else { return nil }
            let matches = ["--user-data-dir=\(directory)", "--user-data-dir \(directory)"].contains { marker in
                guard let found = command.range(of: marker) else { return false }
                return found.upperBound == command.endIndex || command[found.upperBound] == " "
            }
            return matches ? pid : nil
        }
        .sorted()
    }

    static func originalExecutableMarker(appPath: String) -> String {
        "/\(URL(fileURLWithPath: appPath).lastPathComponent)/Contents/MacOS/"
    }

    /// 命令列的執行檔是某個 App 的主執行檔，不是包在 `Contents/Frameworks` 等處的 Helper，
    /// 也不是把它當參數的別的程式（VS Code 啟動時會跑 `/bin/zsh -i -l -c '…/Code'` 讀 shell 環境）。
    static func isMainExecutable(_ command: String) -> Bool {
        guard let range = command.range(of: ".app/Contents/MacOS/") else { return false }
        let prefix = command[..<range.lowerBound]
        return !prefix.contains("/Contents/") && !prefix.contains("'") && !prefix.contains("\"")
    }

    /// 主程序命令列所屬的 App 路徑（到 `.app` 為止）。
    static func bundlePath(fromCommand command: String) -> String? {
        guard isMainExecutable(command), let range = command.range(of: ".app/Contents/MacOS/") else { return nil }
        return String(command[..<range.lowerBound]) + ".app"
    }

    /// App 自己的更新程式（Squirrel 的 ShipIt、Sparkle 的 Autoupdate）是否在等待安裝：原本的 App，
    /// 以及 `cloneFolders` 這些實例的複本。Squirrel 只等同一個路徑的程序結束才換掉 App。
    static func updaterProcessIDs(appPath: String, cloneFolders: Set<String> = [], in processes: [Int32: String]) -> [Int32] {
        let app = "/\(URL(fileURLWithPath: appPath).lastPathComponent)/Contents/Frameworks/"
        return processes.compactMap { pid, command in
            let isShipIt = command.contains("/Contents/Frameworks/Squirrel.framework/Resources/ShipIt")
            let isSparkle = command.contains("/Contents/Frameworks/Sparkle.framework/") && command.contains("/Autoupdate")
            guard isShipIt || isSparkle else { return nil }
            if let folder = AppCloneService.instanceFolder(inPath: command) {
                return cloneFolders.contains(folder) ? pid : nil
            }
            return command.contains(app) ? pid : nil
        }
        .sorted()
    }

    /// Claude 桌面 App 實例目前登入的帳號編號；沒登入、讀不到或格式不對都回 nil。
    /// 預設實例讀官方 App 自己的資料夾。只讀 `config.json`，不碰加密的登入資料。
    func claudeSignedInAccountUUID(for instance: Instance, isDefault: Bool) -> String? {
        guard instance.platform == .claude else { return nil }
        let directory: URL
        if isDefault {
            guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
            directory = support.appending(path: "Claude", directoryHint: .isDirectory)
        } else {
            directory = URL(fileURLWithPath: instance.profileDirectory)
        }
        guard let data = try? Data(contentsOf: directory.appending(path: "config.json")) else { return nil }
        return Self.parseClaudeSignedInAccountUUID(data)
    }

    /// `lastKnownAccountUuid` 登出後可能還留著，所以另外要求登入 token 快取存在才算登入中。
    static func parseClaudeSignedInAccountUUID(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = root["lastKnownAccountUuid"] as? String, UUID(uuidString: value) != nil,
              root.contains(where: { $0.key.hasPrefix("oauth:tokenCache") && !(($0.value as? String) ?? "").isEmpty }) else { return nil }
        return value.lowercased()
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

    /// 資料夾名稱取 UUID 前 8 碼：VS Code 會在資料夾內建立 IPC socket，完整 UUID 會超過 macOS 104 字元的 socket 路徑上限而啟動失敗。
    func profileDirectory(for id: UUID) throws -> String {
        let root = try instancesRootURL()
        let hex = id.uuidString.replacingOccurrences(of: "-", with: "")
        for length in stride(from: 8, through: hex.count, by: 4) {
            let candidate = root.appending(path: String(hex.prefix(length)), directoryHint: .isDirectory)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate.path }
        }
        return root.appending(path: id.uuidString, directoryHint: .isDirectory).path
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
    case executableMissing, unsafeProfilePath, launchFailed, quitTimedOut, removeQuitTimedOut, updateQuitTimedOut, updateTimedOut
    var errorDescription: String? {
        switch self {
        case .executableMissing: "找不到 App"
        case .unsafeProfilePath: "拒絕刪除不在 AspaceI 管理範圍內的資料夾"
        case .launchFailed: "App 啟動失敗"
        case .quitTimedOut: "App 沒有在時間內關閉，未切換帳號"
        case .removeQuitTimedOut: "App 沒有在時間內關閉，未刪除實例"
        case .updateQuitTimedOut: "App 沒有在時間內關閉，未更新"
        case .updateTimedOut: "更新沒有在時間內完成"
        }
    }
}
