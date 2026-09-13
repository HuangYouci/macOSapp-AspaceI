import Foundation
import Testing
@testable import AspaceI

struct LocalAccountDiscoveryServiceTests {
    @Test
    func discoversOnlyExistingCredentialStores() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appending(path: ".codex", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        let authFile = root.appending(path: ".codex/auth.json")
        try Data().write(to: authFile)

        let candidates = LocalAccountDiscoveryService.shared.discover(homeDirectory: root)

        #expect(candidates == [
            LocalAccountCandidate(platform: .codex, sourceDescription: "auth.json")
        ])
    }
}
