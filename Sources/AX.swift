import AppKit
import ApplicationServices

/// Thin wrapper over the Accessibility API. Every call is best-effort: apps are
/// free to ignore us, so nothing here throws — it just returns nil and we move on.
enum AX {

    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    // MARK: - Attribute plumbing

    private static func copyAttribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func axValue(_ element: AXUIElement, _ name: String, _ type: AXValueType) -> AXValue? {
        guard let value = copyAttribute(element, name),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let boxed = value as! AXValue
        return AXValueGetType(boxed) == type ? boxed : nil
    }

    // MARK: - Reading

    static func role(_ element: AXUIElement) -> String? {
        copyAttribute(element, kAXRoleAttribute) as? String
    }

    static func subrole(_ element: AXUIElement) -> String? {
        copyAttribute(element, kAXSubroleAttribute) as? String
    }

    static func parent(_ element: AXUIElement) -> AXUIElement? {
        guard let value = copyAttribute(element, kAXParentAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func pid(_ element: AXUIElement) -> pid_t? {
        var result: pid_t = 0
        return AXUIElementGetPid(element, &result) == .success ? result : nil
    }

    static func origin(_ element: AXUIElement) -> CGPoint? {
        guard let boxed = axValue(element, kAXPositionAttribute, .cgPoint) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(boxed, .cgPoint, &point) ? point : nil
    }

    static func size(_ element: AXUIElement) -> CGSize? {
        guard let boxed = axValue(element, kAXSizeAttribute, .cgSize) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(boxed, .cgSize, &size) ? size : nil
    }

    // MARK: - Writing

    /// True when the window will actually let us move it. Rules out things like
    /// the desktop, the Dock, and most system panels before we bother the user
    /// with an overlay.
    static func isMovable(_ element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }

    static func isResizable(_ element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }

    private static func application(owning element: AXUIElement) -> AXUIElement? {
        guard let pid = pid(element) else { return nil }
        return AXUIElementCreateApplication(pid)
    }

    private static let enhancedUserInterface = "AXEnhancedUserInterface"

    private static func isEnhanced(_ app: AXUIElement) -> Bool {
        (copyAttribute(app, enhancedUserInterface) as? Bool) ?? false
    }

    private static func setEnhanced(_ app: AXUIElement, _ on: Bool) {
        AXUIElementSetAttributeValue(app, enhancedUserInterface as CFString, on as CFTypeRef)
    }

    struct FrameWriteResult {
        var target: CGRect
        var before: CGRect?
        var after: CGRect?
        var positionSettable = false
        var sizeSettable = false
        var hadEnhancedUI = false
        var errors: [String] = []

        var resized: Bool {
            guard let after else { return false }
            return abs(after.width - target.width) < 2 && abs(after.height - target.height) < 2
        }
    }

    /// Writes a window's frame, working around the two things that usually make
    /// a window move but refuse to resize:
    ///
    ///  1. `AXEnhancedUserInterface`. AppKit apps that have it on — Electron and
    ///     Java apps commonly do, and any app does after VoiceOver has run —
    ///     animate programmatic geometry changes and drop the resize on the
    ///     floor. It has to be switched off around the write and put back.
    ///  2. Clamping order. An app asked to move to the left edge while still at
    ///     its old width may refuse; asked to resize first, it may refuse a size
    ///     that would push it off the right edge. Writing size, position, size
    ///     satisfies both orderings, and ending on a size write means a clamped
    ///     resize gets a second attempt from the correct position.
    @discardableResult
    static func setFrame(_ element: AXUIElement, _ rect: CGRect) -> FrameWriteResult {
        var result = FrameWriteResult(target: rect)
        result.before = frame(element)
        result.positionSettable = isMovable(element)
        result.sizeSettable = isResizable(element)

        let app = application(owning: element)
        if let app, isEnhanced(app) {
            result.hadEnhancedUI = true
            setEnhanced(app, false)
        }
        defer {
            if result.hadEnhancedUI, let app { setEnhanced(app, true) }
        }

        var origin = rect.origin
        var size = rect.size
        guard let originValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            result.errors.append("AXValueCreate failed")
            return result
        }

        func write(_ attribute: String, _ value: AXValue, _ label: String) {
            let status = AXUIElementSetAttributeValue(element, attribute as CFString, value)
            if status != .success {
                result.errors.append("\(label)=\(status.rawValue)")
            }
        }

        write(kAXSizeAttribute, sizeValue, "size1")
        write(kAXPositionAttribute, originValue, "position")
        write(kAXSizeAttribute, sizeValue, "size2")

        result.after = frame(element)
        return result
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let origin = origin(element), let size = size(element) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    // MARK: - Hit testing

    /// Walks up from whatever element sits under the cursor until it finds the
    /// enclosing window. The cursor usually lands on a title bar or toolbar, so
    /// the window is a few hops up the parent chain.
    static func window(at point: CGPoint) -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)

        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              var element = hit else { return nil }

        for _ in 0..<15 {
            if role(element) == kAXWindowRole { return element }
            guard let next = parent(element) else { return nil }
            element = next
        }
        return nil
    }
}
