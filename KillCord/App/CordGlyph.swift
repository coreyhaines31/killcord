import AppKit

/// The menu bar glyph: a plug on a short cord. Drawn in code as a template image so it matches the menu bar,
/// tinted when spend passes a threshold. A placeholder until there's a real mark.
enum CordGlyph {
    static func image(tint: NSColor?, size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let scale = rect.width / 18
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
            }
            let color = tint ?? .black
            color.setStroke()
            color.setFill()

            // Prongs.
            for x: CGFloat in [6.6, 10.2] {
                NSBezierPath(roundedRect: NSRect(origin: point(x, 13), size: NSSize(width: 1.4 * scale, height: 4 * scale)),
                             xRadius: 0.6 * scale, yRadius: 0.6 * scale).fill()
            }
            // Plug body.
            let body = NSBezierPath(roundedRect: NSRect(origin: point(4.4, 7.4),
                                                        size: NSSize(width: 9.2 * scale, height: 6 * scale)),
                                    xRadius: 1.8 * scale, yRadius: 1.8 * scale)
            body.lineWidth = 1.4 * scale
            body.stroke()
            // Cord.
            let cord = NSBezierPath()
            cord.move(to: point(9, 7.4))
            cord.curve(to: point(4, 1.4), controlPoint1: point(9, 3.6), controlPoint2: point(6, 2.6))
            cord.lineWidth = 1.4 * scale
            cord.lineCapStyle = .round
            cord.stroke()
            return true
        }
        image.isTemplate = tint == nil
        image.accessibilityDescription = "Kill Cord"
        return image
    }
}
