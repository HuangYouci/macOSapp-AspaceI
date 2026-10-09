import Testing
@testable import AspaceI

struct ShortLabelTests {
    @Test("沒撞名時就是前三字，保留大小寫與符號")
    func usesFirstThreeCharacters() {
        #expect(ShortLabel.labels(for: ["huangyouci", "octocat", "Codex", "yc"]) == ["hua", "oct", "Cod", "yc"])
    }

    @Test("前三字相同：保留前兩字，第三字取各自第一個不同的字")
    func takesFirstDifferingCharacter() {
        #expect(ShortLabel.labels(for: ["yc.huang", "yc.hsu"]) == ["ycu", "ycs"])
        #expect(ShortLabel.labels(for: ["support", "superman", "other"]) == ["sup", "sue", "oth"])
    }

    @Test("三個以上撞名：先分出獨一的，剩下同組的繼續往後比")
    func resolvesLargerGroups() {
        #expect(ShortLabel.labels(for: ["abcx1", "abcx2", "abcy"]) == ["ab1", "ab2", "aby"])
    }

    @Test("一個名稱比到結束：它保留原本的前三字，另一個取不同的字")
    func keepsNameThatEnds() {
        #expect(ShortLabel.labels(for: ["abc", "abcd"]) == ["abc", "abd"])
    }

    @Test("比到最後都相同就依順序編號 1、2、3")
    func numbersIdenticalNames() {
        #expect(ShortLabel.labels(for: ["yc", "yc", "yc"]) == ["yc1", "yc2", "yc3"])
        #expect(ShortLabel.labels(for: ["abc", "abc", "abcd"]) == ["ab1", "ab2", "abd"])
    }

    @Test("中文以字為單位")
    func handlesCJK() {
        #expect(ShortLabel.labels(for: ["工作帳號甲", "工作帳號乙"]) == ["工作甲", "工作乙"])
    }
}
