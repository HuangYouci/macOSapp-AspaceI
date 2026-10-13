import CoreGraphics
import Foundation
import Testing
@testable import AspaceI

struct DisplaySwapTests {
    // 左邊 1440x900 筆電（選單列 25），右邊 2560x1440 外接螢幕（選單列 25、Dock 在底部 80）。
    private let laptop = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let laptopVisible = CGRect(x: 0, y: 25, width: 1440, height: 875)
    private let external = CGRect(x: 1440, y: -200, width: 2560, height: 1440)
    private let externalVisible = CGRect(x: 1440, y: -175, width: 2560, height: 1335)

    @Test("佔滿可用區域的視窗換過去仍佔滿")
    func maximizedStaysMaximized() {
        let mapped = DisplaySwapGeometry.mapped(laptopVisible, from: laptopVisible, to: externalVisible)
        #expect(mapped == externalVisible)
    }

    @Test("左半邊的視窗換過去仍在左半邊")
    func halfKeepsProportion() {
        let left = CGRect(x: 0, y: 25, width: 720, height: 875)
        let mapped = DisplaySwapGeometry.mapped(left, from: laptopVisible, to: externalVisible)
        #expect(mapped == CGRect(x: 1440, y: -175, width: 1280, height: 1335))
    }

    @Test("超出螢幕邊界的視窗會被收回目標區域內")
    func clampsIntoTarget() {
        let overflowing = CGRect(x: 1300, y: 800, width: 400, height: 300)
        let mapped = DisplaySwapGeometry.mapped(overflowing, from: laptopVisible, to: externalVisible)
        #expect(mapped.maxX <= externalVisible.maxX)
        #expect(mapped.maxY <= externalVisible.maxY)
        #expect(mapped.minX >= externalVisible.minX)
    }

    @Test("跨兩個螢幕的視窗算在重疊面積大的那一邊")
    func assignsByLargestOverlap() {
        let mostlyRight = CGRect(x: 1340, y: 100, width: 800, height: 600)
        #expect(DisplaySwapGeometry.index(of: mostlyRight, in: [laptop, external]) == 1)
        let offScreen = CGRect(x: -3000, y: 0, width: 100, height: 100)
        #expect(DisplaySwapGeometry.index(of: offScreen, in: [laptop, external]) == nil)
    }

    @Test("兩邊一起換，第三個螢幕上的視窗不動")
    func plansBothDirectionsOnly() {
        let third = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let windows = [
            CGRect(x: 100, y: 100, width: 400, height: 300),
            CGRect(x: 2000, y: 0, width: 800, height: 600),
            CGRect(x: -1000, y: 100, width: 400, height: 300)
        ]
        let moves = DisplaySwapGeometry.plan(
            windows: windows,
            screens: [laptop, external, third],
            visible: [laptopVisible, externalVisible, third],
            first: 0,
            second: 1
        )
        #expect(moves.keys.sorted() == [0, 1])
        #expect(moves[0].map { external.contains(CGPoint(x: $0.midX, y: $0.midY)) } == true)
        #expect(moves[1].map { laptop.contains(CGPoint(x: $0.midX, y: $0.midY)) } == true)
    }

    @Test("快捷鍵依 ⌃⌥⇧⌘ 順序顯示")
    func shortcutDisplayOrder() {
        let shortcut = KeyShortcut(
            keyCode: 1,
            modifiers: KeyShortcut.command | KeyShortcut.control | KeyShortcut.shift | KeyShortcut.option,
            keyLabel: "S"
        )
        #expect(shortcut.displayString == "⌃⌥⇧⌘S")
    }

    @Test("只有 Shift 或沒有修飾鍵的組合不接受")
    func requiresRealModifier() {
        #expect(!KeyShortcut(keyCode: 1, modifiers: 0, keyLabel: "S").isUsable)
        #expect(!KeyShortcut(keyCode: 1, modifiers: KeyShortcut.shift, keyLabel: "S").isUsable)
        #expect(KeyShortcut(keyCode: 1, modifiers: KeyShortcut.option | KeyShortcut.shift, keyLabel: "S").isUsable)
    }

    @Test("特殊鍵用符號，其餘取字元轉大寫")
    func keyLabels() {
        #expect(KeyShortcut.label(keyCode: 124, characters: nil) == "→")
        #expect(KeyShortcut.label(keyCode: 49, characters: " ") == "Space")
        #expect(KeyShortcut.label(keyCode: 1, characters: "s") == "S")
        #expect(KeyShortcut.label(keyCode: 200, characters: "") == "#200")
    }

    @Test("組合存檔後讀回內容不變")
    func ruleRoundTrip() throws {
        let rule = DisplaySwapRule(
            first: DisplayReference(uuid: "A", name: "內建顯示器"),
            second: DisplayReference(uuid: "B", name: "DELL U2720Q"),
            shortcut: KeyShortcut(keyCode: 1, modifiers: KeyShortcut.control | KeyShortcut.option, keyLabel: "S")
        )
        let decoded = try JSONDecoder().decode([DisplaySwapRule].self, from: JSONEncoder().encode([rule]))
        #expect(decoded == [rule])
    }
}
