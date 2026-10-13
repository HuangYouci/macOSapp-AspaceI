import ApplicationServices
import CoreGraphics

/// 透過 Accessibility 讀寫其他 App 的視窗。呼叫端要先取得輔助使用權限。
enum AXWindow {
    /// 每改一次大小 App 就重排一次畫面，呼叫越少越快：
    /// 一樣大只移位置；變小先縮再移、變大先移再放，避免中途超出螢幕被 App 拒絕；長寬一增一減時才多補一次大小。
    static func move(_ window: AXUIElement, from current: CGRect, to target: CGRect) -> Bool {
        var size = target.size
        var origin = target.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size),
              let originValue = AXValueCreate(.cgPoint, &origin) else { return false }
        let setSize = { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue) }
        let setPosition = { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, originValue) }
        if current.size == target.size {
            return setPosition() == .success
        }
        let shrinks = target.width <= current.width && target.height <= current.height
        let grows = target.width >= current.width && target.height >= current.height
        if shrinks {
            _ = setSize()
            return setPosition() == .success
        }
        if grows {
            let positionError = setPosition()
            _ = setSize()
            return positionError == .success
        }
        _ = setSize()
        let positionError = setPosition()
        _ = setSize()
        return positionError == .success
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let positionValue = attribute(window, kAXPositionAttribute),
              let sizeValue = attribute(window, kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        // CF 型別無法用 as? 檢查，上面已比對過型別編號，這裡才轉。
        guard AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    /// 拉到最前面。只拉視窗不夠，App 本身也要叫到前景，鍵盤輸入才會進去。
    static func raise(_ window: AXUIElement) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
    }

    static func title(of window: AXUIElement) -> String {
        attribute(window, kAXTitleAttribute) as? String ?? ""
    }
}
