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
