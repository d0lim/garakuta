import AppKit

/// The app mark reduced to a menu bar glyph: an open cardboard box, drawn as a template image so the system tints it
/// for light, dark and highlighted menu bars. Drawn with paths rather than shipped as bitmaps so it stays sharp at
/// every scale factor.
@MainActor
enum AppGlyph {
    static let size = NSSize(width: 18, height: 18)

    static func image(accessibilityDescription: String) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            draw()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    private static func draw() {
        NSColor.black.setFill()
        // Front face, seen slightly from above so the rim is wider than the base.
        let body = NSBezierPath()
        body.move(to: NSPoint(x: 3.9, y: 2.4))
        body.line(to: NSPoint(x: 14.1, y: 2.4))
        body.line(to: NSPoint(x: 14.9, y: 9.6))
        body.line(to: NSPoint(x: 3.1, y: 9.6))
        body.close()
        body.fill()
        // Handle slot knocked out of the front face.
        let slot = NSBezierPath(roundedRect: NSRect(x: 7.3, y: 4.9, width: 3.4, height: 1.3), xRadius: 0.65, yRadius: 0.65)
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        slot.fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        // Side flaps folded outwards, back flaps rising behind the rim.
        flap(hinge: NSPoint(x: 4.5, y: 9.0), dir: -1, degrees: 34, length: 4.4).fill()
        flap(hinge: NSPoint(x: 13.5, y: 9.0), dir: 1, degrees: 34, length: 4.4).fill()
        flap(hinge: NSPoint(x: 5.6, y: 9.3), dir: 1, degrees: 62, length: 5.6).fill()
        flap(hinge: NSPoint(x: 12.4, y: 9.3), dir: -1, degrees: 62, length: 5.6).fill()
    }

    /// A flap is a thick bar hinged on the rim. `dir` is -1 for leftwards, 1 for rightwards.
    private static func flap(hinge: NSPoint, dir: CGFloat, degrees: CGFloat, length: CGFloat, thickness: CGFloat = 2.2) -> NSBezierPath {
        let angle = degrees * .pi / 180
        let d = NSPoint(x: dir * cos(angle), y: sin(angle))
        let n = NSPoint(x: -dir * sin(angle) * thickness / 2, y: cos(angle) * thickness / 2)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: hinge.x - n.x, y: hinge.y - n.y))
        path.line(to: NSPoint(x: hinge.x + d.x * length - n.x, y: hinge.y + d.y * length - n.y))
        path.line(to: NSPoint(x: hinge.x + d.x * length + n.x, y: hinge.y + d.y * length + n.y))
        path.line(to: NSPoint(x: hinge.x + n.x, y: hinge.y + n.y))
        path.close()
        return path
    }
}
