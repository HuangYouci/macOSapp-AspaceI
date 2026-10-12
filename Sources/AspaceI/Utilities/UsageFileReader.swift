import Darwin
import Foundation

/// 記錄檔動輒數 GB，絕大多數的行與用量無關。先以位元組比對找出含關鍵字的行，只有那些行才交給呼叫端解析。
enum UsageFileReader {
    /// 從 `offset` 起，對每一個含有任一 `patterns` 的完整行（不含換行）依序呼叫 `body`。
    /// 回傳處理到的位置：最後一個換行的下一個位元組；結尾沒有換行的半行留給下次（檔案還在寫）。
    static func scanLines(of url: URL, from offset: Int, patterns: [String], body: (Data) -> Void) throws -> Int {
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        guard offset >= 0, offset < data.count else { return min(max(offset, 0), data.count) }
        let needles = patterns.map { Array($0.utf8) }
        let anchors = needles.map { rarestIndex(in: $0) }
        return data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Int in
            guard let base = buffer.baseAddress else { return offset }
            // 沒有這個提示，mmap 逐頁缺頁讀磁碟，數 GB 的檔案要讀幾十秒。
            madvise(UnsafeMutableRawPointer(mutating: base), buffer.count, MADV_SEQUENTIAL)
            let newline = Int32(UInt8(ascii: "\n"))
            guard let lastNewline = lastIndex(of: UInt8(newline), in: buffer, from: offset, to: buffer.count) else { return offset }
            let end = lastNewline + 1
            // 每個關鍵字各自記住下一個出現的位置，游標超過了才重找。
            var hits = [Int?](repeating: nil, count: needles.count)
            var searched = [Bool](repeating: false, count: needles.count)
            var cursor = offset
            while cursor < end {
                var next: Int?
                for index in needles.indices {
                    if !searched[index] || (hits[index].map { $0 < cursor } ?? false) {
                        searched[index] = true
                        hits[index] = find(needles[index], anchor: anchors[index], in: base, from: cursor, to: end)
                    }
                    if let hit = hits[index], next.map({ hit < $0 }) ?? true { next = hit }
                }
                guard let hit = next else { break }
                let lineStart = lastIndex(of: UInt8(newline), in: buffer, from: cursor, to: hit).map { $0 + 1 } ?? cursor
                let lineEnd = memchr(base + hit, newline, end - hit).map { base.distance(to: $0) } ?? end
                body(Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: base + lineStart), count: lineEnd - lineStart, deallocator: .none))
                cursor = lineEnd + 1
            }
            return end
        }
    }

    /// Darwin 的 `memmem` 每秒只掃得動兩三百 MB（2026-10-12 實測 7.5GB 要 40 秒）。
    /// 改用有向量化的 `memchr` 找關鍵字裡最少見的那個位元組，找到了再比對整段。
    private static func find(_ needle: [UInt8], anchor: Int, in base: UnsafeRawPointer, from lower: Int, to upper: Int) -> Int? {
        guard !needle.isEmpty else { return nil }
        var position = lower
        while position + needle.count <= upper {
            let searchStart = position + anchor
            guard let found = memchr(base + searchStart, Int32(needle[anchor]), upper - searchStart) else { return nil }
            let candidate = base.distance(to: found) - anchor
            guard candidate + needle.count <= upper else { return nil }
            if needle.withUnsafeBytes({ memcmp(base + candidate, $0.baseAddress, needle.count) }) == 0 { return candidate }
            position = candidate + 1
        }
        return nil
    }

    /// 越後面越少見；不在表裡的（大寫、數字）當成最少見。
    private static let commonBytes = Array("\" :,{}[]_-etaoinsrhldcumfpgwybvkxjqz".utf8)

    static func rarestIndex(in needle: [UInt8]) -> Int {
        var best = 0
        var bestRank = -1
        for (index, byte) in needle.enumerated() {
            let rank = commonBytes.firstIndex(of: byte) ?? Int.max
            if rank > bestRank {
                best = index
                bestRank = rank
            }
        }
        return best
    }

    /// Darwin 沒有 `memrchr`。往回找的距離最多一行，逐位元組掃就夠。
    private static func lastIndex(of byte: UInt8, in buffer: UnsafeRawBufferPointer, from lower: Int, to upper: Int) -> Int? {
        var index = upper - 1
        while index >= lower {
            if buffer[index] == byte { return index }
            index -= 1
        }
        return nil
    }
}
