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
        #expect(InstanceService.openArguments(for: codex, appPath: codex.executablePath, isDefault: false) == [
            "-n", "--env", "CODEX_HOME=/p/codex", "--env", "CODEX_ELECTRON_USER_DATA_PATH=/p/codex/app-data",
            "-a", "/Applications/Codex.app", "--args", "--user-data-dir=/p/codex/app-data"
        ])
        #expect(InstanceService.openArguments(for: vscode, appPath: vscode.executablePath, isDefault: false) == [
            "-n", "-a", "/Applications/Visual Studio Code.app", "--args", "--user-data-dir=/p/vscode"
        ])
        // 預設實例也要 -n，否則其他實例在跑時 open 只會把其中一個叫到前面。
        #expect(InstanceService.openArguments(for: vscode, appPath: vscode.executablePath, isDefault: true) == ["-n", "-a", "/Applications/Visual Studio Code.app"])
        // 非預設實例開的是複本，資料夾參數不變。
        let clone = "/u/Library/Application Support/AspaceI/Apps.noindex/ab12cd34/Visual Studio Code - yc.app"
        #expect(InstanceService.openArguments(for: vscode, appPath: clone, isDefault: false) == [
            "-n", "-a", clone, "--args", "--user-data-dir=/p/vscode"
        ])
    }

    @Test("依主執行檔與 user-data-dir 區分預設與獨立實例，忽略 Helper 程序")
    func matchesRunningProcesses() {
        let list = InstanceService.parseProcessList("""
          101 /Applications/Visual Studio Code.app/Contents/MacOS/Code
          202 /Applications/Visual Studio Code.app/Contents/MacOS/Code --user-data-dir /p/vscode
          303 /Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper --user-data-dir /p/vscode
          404 /Applications/Codex.app/Contents/MacOS/Codex --user-data-dir=/p/codex/app-data
          505 /private/var/folders/T/AppTranslocation/X/d/Visual Studio Code.app/Contents/MacOS/Code --user-data-dir=/p/vscode-2
          606 /Applications/Visual Studio Code.app/Contents/MacOS/Code --user-data-dir=/p/vscode-extra
        """)
        #expect(list.count == 6)
        #expect(InstanceService.mainProcessIDs(for: vscode, isDefault: true, in: list) == [101])
        #expect(InstanceService.mainProcessIDs(for: vscode, isDefault: false, in: list) == [202])
        #expect(InstanceService.mainProcessIDs(for: codex, isDefault: false, in: list) == [404])
        let translocated = Instance(name: "VS Code 3", platform: .githubCopilot, profileDirectory: "/p/vscode-2", executablePath: "/Applications/Visual Studio Code.app")
        #expect(InstanceService.mainProcessIDs(for: translocated, isDefault: false, in: list) == [505])
    }

    @Test("複本：非預設實例不管 App 檔名只認資料夾；被裸開的複本不算預設實例；Helper 與 Claude Code 子程序不算")
    func matchesCloneProcesses() {
        let claude = Instance(name: "1-big", platform: .claude, profileDirectory: "/p/claude", executablePath: "/Applications/Claude.app")
        let root = "/u/Library/Application Support/AspaceI/Apps.noindex/1cbfe5af"
        let list = InstanceService.parseProcessList("""
          1 \(root)/Claude - yc.app/Contents/MacOS/Claude --user-data-dir=/p/claude
          2 \(root)/Claude - yc.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper --type=gpu-process --user-data-dir=/p/claude
          3 \(root)/Claude.app/Contents/MacOS/Claude
          4 /Applications/Claude.app/Contents/MacOS/Claude
          5 /p/claude/claude-code/2.1/x/claude.app/Contents/MacOS/claude --output-format stream-json
          6 /bin/zsh -i -l -c '/Applications/Claude.app/Contents/MacOS/Claude' -p 'x'
        """)
        #expect(InstanceService.mainProcessIDs(for: claude, isDefault: false, in: list) == [1])
        #expect(InstanceService.mainProcessIDs(for: claude, isDefault: true, in: list) == [4])
        #expect(InstanceService.bundlePath(fromCommand: list[1] ?? "") == "\(root)/Claude - yc.app")
        #expect(InstanceService.bundlePath(fromCommand: list[2] ?? "") == nil)
        #expect(InstanceService.bundlePath(fromCommand: list[6] ?? "") == nil)
    }

    @Test("偵測等待安裝的 ShipIt 與 Sparkle：原本的 App 加上指定實例的複本，不認 Helper、別的 App、別的實例")
    func detectsPendingUpdaters() {
        let list = InstanceService.parseProcessList("""
          10 /Applications/Claude.app/Contents/MacOS/Claude --user-data-dir=/p/claude
          11 /Applications/Claude.app/Contents/Frameworks/Squirrel.framework/Resources/ShipIt com.anthropic.claudefordesktop.ShipIt /Users/u/Library/Caches/com.anthropic.claudefordesktop.ShipIt/ShipItState.plist
          20 /Applications/ChatGPT.app/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate com.openai.codex /Users/u u
          21 /Users/u/Library/Caches/com.openai.codex/org.sparkle-project.Sparkle/Launcher/X/Updater.app/Contents/MacOS/Updater /Applications/ChatGPT.app 0
          22 /Applications/ChatGPT.app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader
          30 /Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper --type=renderer
          40 /Applications/Claude Beta.app/Contents/Frameworks/Squirrel.framework/Resources/ShipIt x
          50 /u/Library/Application Support/AspaceI/Apps.noindex/1cbfe5af/Claude.app/Contents/Frameworks/Squirrel.framework/Resources/ShipIt y
        """)
        #expect(InstanceService.updaterProcessIDs(appPath: "/Applications/Claude.app", in: list) == [11])
        #expect(InstanceService.updaterProcessIDs(appPath: "/Applications/Claude.app", cloneFolders: ["1cbfe5af"], in: list) == [11, 50])
        #expect(InstanceService.updaterProcessIDs(appPath: "/Applications/Claude.app", cloneFolders: ["ffffffff"], in: list) == [11])
        #expect(InstanceService.updaterProcessIDs(appPath: "/Applications/ChatGPT.app", in: list) == [20])
        #expect(InstanceService.updaterProcessIDs(appPath: "/Applications/Visual Studio Code.app", in: list).isEmpty)
    }

    @Test("Claude 實例登入帳號：要有帳號編號與 token 快取才算登入中")
    func parsesClaudeSignedInAccount() {
        let uuid = "A1579349-DF6C-4B51-B782-A15C70F8C35B"
        let signedIn = Data(#"{"lastKnownAccountUuid":"\#(uuid)","oauth:tokenCacheV2":"djEw"}"#.utf8)
        #expect(InstanceService.parseClaudeSignedInAccountUUID(signedIn) == uuid.lowercased())
        let signedOut = Data(#"{"lastKnownAccountUuid":"\#(uuid)"}"#.utf8)
        #expect(InstanceService.parseClaudeSignedInAccountUUID(signedOut) == nil)
        let emptyCache = Data(#"{"lastKnownAccountUuid":"\#(uuid)","oauth:tokenCache":""}"#.utf8)
        #expect(InstanceService.parseClaudeSignedInAccountUUID(emptyCache) == nil)
        #expect(InstanceService.parseClaudeSignedInAccountUUID(Data(#"{"lastKnownAccountUuid":"not-a-uuid","oauth:tokenCache":"x"}"#.utf8)) == nil)
        #expect(InstanceService.parseClaudeSignedInAccountUUID(Data("壞掉".utf8)) == nil)
    }

    @Test("Claude profile 的帳號編號統一成小寫")
    func parsesClaudeProfileAccountUUID() {
        #expect(QuotaService.parseClaudeAccountUUID(["account": ["uuid": "A1579349-DF6C-4B51-B782-A15C70F8C35B"]]) == "a1579349-df6c-4b51-b782-a15c70f8c35b")
        #expect(QuotaService.parseClaudeAccountUUID(["account": ["uuid": "nope"]]) == nil)
        #expect(QuotaService.parseClaudeAccountUUID([:]) == nil)
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
