import Foundation

/// 選單列與實例 Dock 圖示共用的三字短名稱。
///
/// 規則：取前三字；任兩個前三字相同時保留前兩字，第三字改取該名稱與其他同組名稱第一個不同的字。
/// 一路比到底仍分不出來（名稱完全相同），第三位改用 1、2、3…（依輸入順序）。
enum ShortLabel {
    static let length = 3

    /// 依輸入順序回傳每個名稱的短名稱。
    static func labels(for names: [String]) -> [String] {
        let characters = names.map { Array($0) }
        var result = characters.map { String($0.prefix(length)) }
        let groups = Dictionary(grouping: characters.indices) { result[$0] }
        for indices in groups.values where indices.count > 1 {
            resolve(indices, from: length, characters: characters, into: &result)
        }
        numberRemainingDuplicates(&result, characters: characters)
        return result
    }

    /// 這組名稱的前 `position` 個字都相同；找第一個不全相同的位置，依該位置的字分組，
    /// 只剩自己的就用那個字，仍同組的繼續往後比。
    private static func resolve(_ indices: [Int], from position: Int, characters: [[Character]], into result: inout [String]) {
        var position = position
        while true {
            let chars = indices.map { characters[$0].indices.contains(position) ? characters[$0][position] : nil }
            if chars.allSatisfy({ $0 == nil }) { return }
            if let first = chars.first, first != nil, chars.allSatisfy({ $0 == first }) {
                position += 1
                continue
            }
            let byChar = Dictionary(grouping: indices) { characters[$0].indices.contains(position) ? characters[$0][position] : nil }
            for (char, members) in byChar {
                // 名稱在這裡結束的那個不用改，保留原本的前三字；別人已經改成不同的了。
                guard let char else { continue }
                if members.count == 1 {
                    let index = members[0]
                    result[index] = String(characters[index].prefix(length - 1)) + String(char)
                } else {
                    resolve(members, from: position + 1, characters: characters, into: &result)
                }
            }
            return
        }
    }

    /// 完全相同的名稱、或改完後撞到別人的，第三位改成流水號。
    private static func numberRemainingDuplicates(_ result: inout [String], characters: [[Character]]) {
        let groups = Dictionary(grouping: result.indices) { result[$0] }
        for indices in groups.values where indices.count > 1 {
            for (offset, index) in indices.sorted().enumerated() {
                result[index] = String(characters[index].prefix(length - 1)) + String(offset + 1)
            }
        }
    }
}
