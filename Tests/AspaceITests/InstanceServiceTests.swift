import Foundation
import Testing
@testable import AspaceI

struct InstanceServiceTests {
    private let codex = Instance(name: "Codex 2", platform: .codex, profileDirectory: "/p/codex", executablePath: "/Applications/Codex.app")
    private let vscode = Instance(name: "VS Code 2", platform: .githubCopilot, profileDirectory: "/p/vscode", executablePath: "/Applications/Visual Studio Code.app")

    @Test
    func refusesToTrashProfileOutsideManagedRoot() {
        let instance = Instance(name: "Unsafe", platform: .codex, profileDirectory: "/tmp/not-managed-by-aspacei", executablePath: "/usr/bin/true")
        #expect(throws: InstanceError.self) {
            try InstanceService.shared.trashProfile(for: instance)
        }
    }

    @Test("非預設實例開新程序並隔離資料夾；Codex 另設 CODEX_HOME")
    func buildsOpenArguments() {
        #expect(InstanceService.openArguments(for: codex, isDefault: false) == [
            "-n", "--env", "CODEX_HOME=/p/codex", "-a", "/Applications/Codex.app", "--args", "--user-data-dir", "/p/codex/app-data"
        ])
        #expect(InstanceService.openArguments(for: vscode, isDefault: false) == [
            "-n", "-a", "/Applications/Visual Studio Code.app", "--args", "--user-data-dir", "/p/vscode"
        ])
        #expect(InstanceService.openArguments(for: vscode, isDefault: true) == ["-a", "/Applications/Visual Studio Code.app"])
    }

    @Test("依主執行檔與 user-data-dir 區分預設與獨立實例，忽略 Helper 程序")
    func matchesRunningProcesses() {
        let list = InstanceService.parseProcessList("""
          101 /Applications/Visual Studio Code.app/Contents/MacOS/Code
          202 /Applications/Visual Studio Code.app/Contents/MacOS/Code --user-data-dir /p/vscode
          303 /Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper --user-data-dir /p/vscode
          404 /Applications/Codex.app/Contents/MacOS/Codex --user-data-dir /p/codex/app-data
        """)
        #expect(list.count == 4)
        #expect(InstanceService.mainProcessIDs(for: vscode, isDefault: true, in: list) == [101])
        #expect(InstanceService.mainProcessIDs(for: vscode, isDefault: false, in: list) == [202])
        #expect(InstanceService.mainProcessIDs(for: codex, isDefault: false, in: list) == [404])
    }

    @Test("預設實例 id 依平台固定且互不相同")
    @MainActor
    func defaultInstanceIDsAreStable() {
        let ids = PlatformKind.allCases.map(InstanceManager.defaultID(for:))
        #expect(Set(ids).count == PlatformKind.allCases.count)
        #expect(InstanceManager.defaultID(for: .codex) == InstanceManager.defaultID(for: .codex))
    }

    @Test("instances.json 新舊格式都讀得懂")
    func decodesStoreFile() throws {
        let store = InstanceStoreFile(instances: [codex])
        let decoded = try JSONDecoder().decode(InstanceStoreFile.self, from: JSONEncoder().encode(store))
        #expect(decoded.instances == [codex])
        let withLegacyKey = Data(#"{"instances":[],"defaultAccountIDs":{}}"#.utf8)
        #expect(try JSONDecoder().decode(InstanceStoreFile.self, from: withLegacyKey).instances.isEmpty)
    }
}
