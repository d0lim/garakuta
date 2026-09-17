import ApplicationServices
import CoreGraphics

/// Small Accessibility helpers shared by the enumerator and activator.
enum AX {
    static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    static func bool(_ element: AXUIElement, _ name: String) -> Bool {
        (attribute(element, name) as NSNumber?)?.boolValue ?? false
    }

    static func point(_ element: AXUIElement, _ name: String) -> CGPoint? {
        guard let value: AnyObject = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        // swiftlint:disable:next force_cast
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    static func size(_ element: AXUIElement, _ name: String) -> CGSize? {
        guard let value: AnyObject = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        // swiftlint:disable:next force_cast
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ name: String, _ value: Bool) -> Bool {
        AXUIElementSetAttributeValue(element, name as CFString, value as CFBoolean) == .success
    }

    @discardableResult
    static func perform(_ element: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }
}
