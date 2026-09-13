import Foundation
import Testing
@testable import AspaceI

@Suite("App 定位")
struct ExecutableLocatorServiceTests {
    private let home = URL(fileURLWithPath: "/Users/tester")

    @Test("GitHub Copilot 實例使用 VS Code")
    func copilotUsesVSCode() {
        let paths = ExecutableLocatorService.candidatePaths(for: .githubCopilot, homeDirectory: home)
        #expect(paths.first == "/Applications/Visual Studio Code.app")
    }

    @Test("Antigravity 優先新版 App，其次 IDE，並找使用者 Applications")
    func antigravityCandidates() {
        let located = ExecutableLocatorService.shared.locate(.antigravity, homeDirectory: home, bundleLookup: { _ in nil }) {
            $0 == "/Users/tester/Applications/Antigravity IDE.app"
        }
        #expect(located == "/Users/tester/Applications/Antigravity IDE.app")
    }

    @Test("找不到時回傳 nil")
    func returnsNilWhenMissing() {
        #expect(ExecutableLocatorService.shared.locate(.codex, homeDirectory: home, bundleLookup: { _ in nil }) { _ in false } == nil)
    }

    @Test("Codex 依 bundle id 找到改名後的 ChatGPT.app")
    func findsRenamedCodexByBundleIdentifier() {
        let located = ExecutableLocatorService.shared.locate(.codex, homeDirectory: home, bundleLookup: {
            $0 == "com.openai.codex" ? "/Applications/ChatGPT.app" : nil
        }) { $0 == "/Applications/ChatGPT.app" }
        #expect(located == "/Applications/ChatGPT.app")
    }
}
