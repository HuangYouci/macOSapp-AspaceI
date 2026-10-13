import Foundation

/// 一組要互換的螢幕。螢幕以系統給的 UUID 辨識：`CGDirectDisplayID` 重新接線後可能換號，UUID 不會。
struct DisplaySwapRule: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var first: DisplayReference
    var second: DisplayReference
    var shortcut: KeyShortcut?
}

/// 螢幕名稱一併存下，螢幕沒接上時設定頁仍顯示得出是哪一台。
struct DisplayReference: Codable, Hashable, Sendable {
    var uuid: String
    var name: String
}

/// 全域快捷鍵。`keyCode` 是實體按鍵位置，`modifiers` 用 Carbon 的修飾鍵旗標，兩者直接交給 `RegisterEventHotKey`。
struct KeyShortcut: Codable, Hashable, Sendable {
    static let command: UInt32 = 1 << 8
    static let shift: UInt32 = 1 << 9
    static let option: UInt32 = 1 << 11
    static let control: UInt32 = 1 << 12

    var keyCode: UInt32
    var modifiers: UInt32
    /// 錄製當下鍵盤配置印在這顆鍵上的字，換配置後顯示可能不同，但觸發的仍是同一顆實體鍵。
    var keyLabel: String

    /// 只按 Shift 或完全不按修飾鍵會吃掉一般打字，不接受。
    var isUsable: Bool {
        modifiers & (Self.command | Self.option | Self.control) != 0
    }

    /// 依 macOS 選單慣例的順序：⌃⌥⇧⌘。
    var displayString: String {
        var text = ""
        if modifiers & Self.control != 0 { text += "⌃" }
        if modifiers & Self.option != 0 { text += "⌥" }
        if modifiers & Self.shift != 0 { text += "⇧" }
        if modifiers & Self.command != 0 { text += "⌘" }
        return text + keyLabel
    }
}

extension KeyShortcut {
    /// 沒有可印字元的按鍵用符號表示，其餘取鍵盤上的字並轉大寫。
    static func label(keyCode: UInt32, characters: String?) -> String {
        if let symbol = specialKeyLabels[keyCode] { return symbol }
        let trimmed = (characters ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "#\(keyCode)" : trimmed.uppercased()
    }

    private static let specialKeyLabels: [UInt32: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
    ]
}
