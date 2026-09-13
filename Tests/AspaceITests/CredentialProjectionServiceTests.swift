import Foundation
import Testing
@testable import AspaceI

struct CredentialProjectionServiceTests {
    @Test
    func projectsCodexCredentialIntoIsolatedProfile() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let account = Account(platform: .codex, displayName: "Codex")
        let credential = Data("{\"tokens\":{}}".utf8)

        try CredentialProjectionService.shared.project(account: account, credentialData: credential, to: root)

        #expect(try Data(contentsOf: root.appending(path: "auth.json")) == credential)
    }

    @Test
    func projectsAntigravityDatabaseFromRecordedSource() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let source = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).vscdb")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source)
        }
        try Data("database".utf8).write(to: source)
        let account = Account(platform: .antigravity, displayName: "Antigravity", sourcePath: source.path)

        try CredentialProjectionService.shared.project(account: account, credentialData: nil, to: root)

        let target = root.appending(path: "User/globalStorage/state.vscdb")
        #expect(try Data(contentsOf: target) == Data("database".utf8))
    }
}
