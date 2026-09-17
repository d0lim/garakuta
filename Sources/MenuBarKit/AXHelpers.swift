import ApplicationServices
import CoreGraphics

/// Type-checked Accessibility attribute readers shared by the scanner and the auto-arranger.
enum AXHelpers {
    static func copyAttribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }

    static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    static func copyElements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let array = value as? [AnyObject] else { return nil }
        return array.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? unsafeDowncast($0, to: AXUIElement.self) : nil }
    }

    static func copyPoint(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let ax = copyAXValue(element, attribute), AXValueGetType(ax) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(ax, .cgPoint, &point) ? point : nil
    }

    static func copySize(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let ax = copyAXValue(element, attribute), AXValueGetType(ax) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(ax, .cgSize, &size) ? size : nil
    }

    private static func copyAXValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXValue.self)
    }
}
