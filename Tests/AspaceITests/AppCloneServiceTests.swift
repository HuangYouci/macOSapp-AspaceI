import Foundation
import Testing
@testable import AspaceI

struct AppCloneServiceTests {
    private let old = URL(fileURLWithPath: "/c/Claude - yc.app")
    private let updated = URL(fileURLWithPath: "/c/Claude.app")

    @Test("複本比原版舊就重做；自己更新過、比原版新就沿用最新那份")
    func picksReusableClone() {
        #expect(AppCloneService.reusableClone([(old, "2.26454.2")], sourceVersion: "2.26454.2") == old)
        #expect(AppCloneService.reusableClone([(old, "2.26454.2")], sourceVersion: "2.31226.0") == nil)
        #expect(AppCloneService.reusableClone([(old, "2.26454.2"), (updated, "2.31226.0")], sourceVersion: "2.26454.2") == updated)
        // 數字比較，不是字串比較：10 比 9 新。
        #expect(AppCloneService.reusableClone([(old, "1.10.0")], sourceVersion: "1.9.0") == old)
        #expect(AppCloneService.reusableClone([(old, nil)], sourceVersion: "1.0") == nil)
        #expect(AppCloneService.reusableClone([], sourceVersion: "1.0") == nil)
    }

    @Test("開過的複本改不了內容：圖示不見或字不對就從最新那份重新複製，不在原地重畫")
    func plansRecloneInsteadOfRepaint() {
        let source = URL(fileURLWithPath: "/Applications/Claude.app")
        // 圖示在、字也對：沿用。
        #expect(AppCloneService.plan(existing: [(old, "2.31226.1", true)], source: source, sourceVersion: "2.31226.1", storedBadge: "sup", badge: "sup") == .reuse(old))
        // 更新程式整包換掉，圖示不見了：從它自己重新複製，保留它較新的版本。
        #expect(AppCloneService.plan(existing: [(old, "2.31226.1", false)], source: source, sourceVersion: "2.31226.0", storedBadge: "sup", badge: "sup") == .reclone(from: old))
        // 帳號換了，圖示上的字要換。
        #expect(AppCloneService.plan(existing: [(old, "2.31226.1", true)], source: source, sourceVersion: "2.31226.1", storedBadge: "sup", badge: "cla") == .reclone(from: old))
        // 舊版程式做的複本沒有記錄字：重做一次。
        #expect(AppCloneService.plan(existing: [(old, "2.31226.1", true)], source: source, sourceVersion: "2.31226.1", storedBadge: nil, badge: "sup") == .reclone(from: old))
        // 比來源舊：從來源重新複製。
        #expect(AppCloneService.plan(existing: [(old, "2.26454.2", true)], source: source, sourceVersion: "2.31226.1", storedBadge: "sup", badge: "sup") == .reclone(from: source))
        #expect(AppCloneService.plan(existing: [], source: source, sourceVersion: "2.31226.1", storedBadge: nil, badge: "sup") == .reclone(from: source))
    }

    @Test("從路徑找出實例資料夾，只認 AspaceI 的複本根目錄")
    func findsInstanceFolder() {
        #expect(AppCloneService.instanceFolder(inPath: "/u/Library/Application Support/AspaceI/Apps.noindex/1cbfe5af/Claude.app") == "1cbfe5af")
        #expect(AppCloneService.instanceFolder(inPath: "/Applications/Claude.app") == nil)
        #expect(AppCloneService.folderName(for: UUID(uuidString: "1CBFE5AF-F7C1-4A5D-92A9-3D8EC27206DF")!) == "1cbfe5af")
    }

    @Test("檔名去掉路徑分隔字元、不以點開頭")
    func sanitizesFileName() {
        #expect(AppCloneService.sanitizedFileName("Claude - a/b:c") == "Claude - a-b-c")
        #expect(AppCloneService.sanitizedFileName(".hidden") == "_.hidden")
    }

    @Test("最新版：數字比較，同版時取排在前面的原本 App，讀不到版本的略過")
    func picksNewestBundle() {
        let original = URL(fileURLWithPath: "/Applications/Claude.app")
        #expect(AppCloneService.newest([(original, "2.26454.2"), (old, "2.26454.2")]) == original)
        #expect(AppCloneService.newest([(original, "2.26454.2"), (old, "2.31226.0"), (updated, nil)]) == old)
        #expect(AppCloneService.newest([(original, "1.9"), (old, "1.10")]) == old)
        #expect(AppCloneService.newest([(original, nil)]) == nil)
    }
}
