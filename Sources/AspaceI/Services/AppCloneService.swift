import AppKit
import Darwin

/// 非預設實例專用的 App 複本。APFS clone 原本的 App，不動 `Contents`、不重簽，只換外層檔名與 Finder 自訂圖示：
/// Dock 顯示的是程序所屬 bundle 的圖示，執行中的程序無法從外部改。
/// 簽章與 bundle id 不變，Keychain、TCC 都當成同一個 App；更新程式也只等同一個路徑的程序，不再互相卡住。
final class AppCloneService: Sendable {
    static let shared = AppCloneService()
    private init() {}

    /// `.noindex` 讓 Spotlight 不收錄；從 Spotlight 直接打開複本會開到預設資料夾。
    static let rootPathComponent = "AspaceI/Apps.noindex"

    /// 準備好這次要啟動的複本並回傳路徑；只在實例沒有執行時呼叫。
    @MainActor
    func prepare(source: URL, instance: Instance, title: String, badge: String) throws -> URL {
        let directory = try directory(for: instance.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let target = directory.appending(path: "\(Self.sanitizedFileName(title)).app", directoryHint: .isDirectory)
        let existing = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "app" }
        let keep = Self.reusableClone(
            existing.map { ($0, Self.bundleVersion(of: $0)) },
            sourceVersion: Self.bundleVersion(of: source)
        )
        for bundle in existing where bundle.standardizedFileURL != keep?.standardizedFileURL {
            try FileManager.default.removeItem(at: bundle)
        }
        if let keep {
            if keep.standardizedFileURL != target.standardizedFileURL {
                try FileManager.default.moveItem(at: keep, to: target)
            }
        } else {
            try Self.clone(source, to: target)
        }
        let icon = InstanceIconRenderer.icon(base: NSWorkspace.shared.icon(forFile: source.path), badge: badge)
        guard NSWorkspace.shared.setIcon(icon, forFile: target.path, options: []) else { throw AppCloneError.iconFailed }
        return target
    }

    func remove(for id: UUID) throws {
        let directory = try directory(for: id)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    func directory(for id: UUID) throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appending(path: Self.rootPathComponent, directoryHint: .isDirectory)
            .appending(path: Self.folderName(for: id), directoryHint: .isDirectory)
    }

    static func folderName(for id: UUID) -> String {
        String(id.uuidString.prefix(8)).lowercased()
    }

    /// 路徑在某個實例的複本資料夾內時回傳資料夾名稱。
    static func instanceFolder(inPath path: String) -> String? {
        guard let range = path.range(of: "/\(rootPathComponent)/") else { return nil }
        let rest = path[range.upperBound...]
        guard let folder = rest.split(separator: "/").first, !folder.isEmpty else { return nil }
        return String(folder)
    }

    static func isClonePath(_ path: String) -> Bool {
        path.contains("/\(rootPathComponent)/")
    }

    /// 複本可能自己更新過（比原版新，而且 ShipIt 會把檔名改回 `Claude.app`），取版本最新的那份；
    /// 比原版舊或讀不到版本就重新複製。
    static func reusableClone(_ candidates: [(url: URL, version: String?)], sourceVersion: String?) -> URL? {
        let newest = candidates
            .compactMap { candidate in candidate.version.map { (candidate.url, $0) } }
            .max { $0.1.compare($1.1, options: .numeric) == .orderedAscending }
        guard let newest else { return nil }
        guard let sourceVersion else { return newest.0 }
        return newest.1.compare(sourceVersion, options: .numeric) == .orderedAscending ? nil : newest.0
    }

    static func sanitizedFileName(_ title: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleaned.hasPrefix(".") ? "_" + cleaned : cleaned).prefix(80))
    }

    /// 直接讀 Info.plist：`Bundle(url:)` 依路徑快取，複本被換掉後還會回舊版本。
    static func bundleVersion(of app: URL) -> String? {
        guard let data = try? Data(contentsOf: app.appending(path: "Contents/Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return (plist["CFBundleVersion"] as? String) ?? (plist["CFBundleShortVersionString"] as? String)
    }

    private static func clone(_ source: URL, to target: URL) throws {
        if clonefile(source.path, target.path, 0) != 0 {
            let code = errno
            // 不同磁碟或檔案系統不支援 clone 時才退回一般複製；其他錯誤照實拋出。
            guard code == ENOTSUP || code == EXDEV else { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
            try FileManager.default.copyItem(at: source, to: target)
        }
        // 原版已經過使用者確認；複本帶著隔離標記換了位置，系統會再問一次或改從暫存路徑執行。
        if removexattr(target.path, "com.apple.quarantine", 0) != 0, errno != ENOATTR {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

enum AppCloneError: LocalizedError {
    case iconFailed
    var errorDescription: String? {
        switch self {
        case .iconFailed: "無法設定實例圖示"
        }
    }
}
