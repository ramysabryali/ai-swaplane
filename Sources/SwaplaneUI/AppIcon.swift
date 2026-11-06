import AppKit

/// The app icon, drawn in code so light and dark variants stay in sync with the brand tokens
/// (midnight, rail, signal orange). Used for the Dock while a window is open and to build `AppIcon.icns`.
@MainActor
public enum AppIconArt {
    /// A 1024-point artboard image for the given appearance.
    public static func image(dark: Bool) -> NSImage {
        NSImage(size: NSSize(width: 1024, height: 1024), flipped: true) { _ in
            draw(dark: dark)
            return true
        }
    }

    private static func draw(dark: Bool) {
        let body = NSRect(x: 100, y: 100, width: 824, height: 824)
        let shape = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)

        // Soft drop shadow under the tile.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.5 : 0.22)
        shadow.shadowBlurRadius = 28
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.set()
        (dark ? NSColor(srgbRed: 0.07, green: 0.11, blue: 0.17, alpha: 1) : NSColor.white).setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()

        // Tile gradient.
        let top = dark ? NSColor(srgbRed: 0.133, green: 0.188, blue: 0.290, alpha: 1) : NSColor(srgbRed: 0.980, green: 0.985, blue: 0.995, alpha: 1)
        let bottom = dark ? NSColor(srgbRed: 0.043, green: 0.071, blue: 0.125, alpha: 1) : NSColor(srgbRed: 0.862, green: 0.894, blue: 0.945, alpha: 1)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        NSGradient(starting: top, ending: bottom)?.draw(from: NSPoint(x: 512, y: 100), to: NSPoint(x: 512, y: 924), options: [])
        NSGraphicsContext.restoreGraphicsState()

        // Fine edge.
        (dark ? NSColor.white.withAlphaComponent(0.10) : NSColor.black.withAlphaComponent(0.08)).setStroke()
        shape.lineWidth = 3
        shape.stroke()

        // Lane fork: one rail splitting into two.
        let rail = dark ? NSColor(srgbRed: 0.910, green: 0.933, blue: 0.969, alpha: 1) : NSColor(srgbRed: 0.043, green: 0.071, blue: 0.125, alpha: 1)
        let signal = NSColor(srgbRed: 1.0, green: 0.541, blue: 0.239, alpha: 1)
        let g = NSBezierPath()
        g.lineWidth = 62
        g.lineCapStyle = .round
        g.move(to: NSPoint(x: 238, y: 512)); g.line(to: NSPoint(x: 410, y: 512))
        g.curve(to: NSPoint(x: 580, y: 352), controlPoint1: NSPoint(x: 500, y: 512), controlPoint2: NSPoint(x: 490, y: 352))
        g.line(to: NSPoint(x: 690, y: 352))
        g.move(to: NSPoint(x: 410, y: 512))
        g.curve(to: NSPoint(x: 580, y: 672), controlPoint1: NSPoint(x: 500, y: 512), controlPoint2: NSPoint(x: 490, y: 672))
        g.line(to: NSPoint(x: 690, y: 672))
        rail.setStroke(); g.stroke()

        func dot(_ y: CGFloat, _ c: NSColor) {
            c.setFill()
            NSBezierPath(ovalIn: NSRect(x: 690, y: y - 62, width: 124, height: 124)).fill()
        }
        dot(352, signal)
        dot(672, dark ? NSColor(srgbRed: 0.435, green: 0.812, blue: 0.592, alpha: 1) : NSColor(srgbRed: 0.357, green: 0.553, blue: 0.937, alpha: 1))
    }

    /// PNG data for an exact pixel size (no Retina doubling).
    static func png(dark: Bool, pixels: Int) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let cg = NSGraphicsContext.current?.cgContext
        cg?.translateBy(x: 0, y: CGFloat(pixels))
        cg?.scaleBy(x: CGFloat(pixels) / 1024, y: -CGFloat(pixels) / 1024)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg!, flipped: true)
        draw(dark: dark)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// Writes `AppIcon.iconset` (light) plus 1024 px previews of both appearances into `dir`.
    public static func writeAssets(to dir: String) {
        let base = URL(fileURLWithPath: dir)
        let set = base.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
        let sizes: [(String, Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for (name, px) in sizes { try? png(dark: false, pixels: px)?.write(to: set.appendingPathComponent(name + ".png")) }
        try? png(dark: false, pixels: 1024)?.write(to: base.appendingPathComponent("icon-light.png"))
        try? png(dark: true, pixels: 1024)?.write(to: base.appendingPathComponent("icon-dark.png"))
    }

    private static var observer: NSKeyValueObservation?

    /// Sets the Dock icon to the light or dark variant and keeps it in step with the appearance.
    public static func installDockIcon() {
        func apply() {
            let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            NSApp.applicationIconImage = image(dark: dark)
        }
        apply()
        observer = NSApp.observe(\.effectiveAppearance, options: [.new]) { _, _ in
            MainActor.assumeIsolated { apply() }
        }
    }
}
