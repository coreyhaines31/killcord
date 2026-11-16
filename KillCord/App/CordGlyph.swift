import AppKit

/// The menu bar glyph: the kill switch from the app icon (housing with its toggle, the key across it,
/// and the coiled lanyard below). Drawn in code from the same geometry as mac-app-kit's
/// Scripts/glyphs/glyphs.mjs, as a template image so it matches the menu bar; tinted when spend
/// passes a threshold.
enum CordGlyph {
    static func image(tint: NSColor?, size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let scale = rect.width / 18
            func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
                NSRect(x: rect.minX + x * scale, y: rect.minY + y * scale, width: width * scale, height: height * scale)
            }
            let color = tint ?? .black
            color.setStroke()
            color.setFill()

            // Housing, outlined.
            let housing = NSBezierPath(roundedRect: box(3.4, 1.4, 11.2, 7.6), xRadius: 1.6 * scale, yRadius: 1.6 * scale)
            housing.lineWidth = 1.4 * scale
            housing.stroke()
            // Toggle.
            NSBezierPath(roundedRect: box(8.1, 2.9, 1.8, 3.2), xRadius: 0.7 * scale, yRadius: 0.7 * scale).fill()
            // The key across the housing.
            NSBezierPath(roundedRect: box(2.6, 6.6, 12.8, 4), xRadius: 1.1 * scale, yRadius: 1.1 * scale).fill()
            // Coiled lanyard.
            for index in 0..<3 {
                let centerY = 12.4 + CGFloat(index) * 1.75
                let coil = NSBezierPath(ovalIn: box(9 - 2.3, centerY - 0.75, 4.6, 1.5))
                coil.lineWidth = 1 * scale
                coil.stroke()
            }
            return true
        }
        image.isTemplate = tint == nil
        image.accessibilityDescription = "Kill Cord"
        return image
    }
}
