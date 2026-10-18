import AppKit

/// Central visual language: black background, dark charcoal surfaces,
/// electric-blue accent, white / light-gray text.
enum Theme {
    // Backgrounds
    static let background = NSColor(hex: 0x0B0E12)        // near-black
    static let surface = NSColor(hex: 0x15191F)           // dark charcoal
    static let surfaceRaised = NSColor(hex: 0x1D222A)     // cards / hover
    static let surfaceHover = NSColor(hex: 0x252B34)
    static let sidebar = NSColor(hex: 0x0E1217)
    static let border = NSColor(hex: 0x2A313B)

    // Accent (electric blue)
    static let accent = NSColor(hex: 0x2E9BFF)
    static let accentDim = NSColor(hex: 0x1B6FC0)
    static let accentSoft = NSColor(hex: 0x2E9BFF).withAlphaComponent(0.15)

    // Text
    static let textPrimary = NSColor(hex: 0xFFFFFF)
    static let textSecondary = NSColor(hex: 0xA7B2BF)
    static let textTertiary = NSColor(hex: 0x6C7682)

    // Status
    static let positive = NSColor(hex: 0x37D67A)
    static let warning = NSColor(hex: 0xFFB020)
    static let negative = NSColor(hex: 0xFF5A5F)

    // Metrics
    static let corner: CGFloat = 10
    static let sidebarWidth: CGFloat = 212
    static let topBarHeight: CGFloat = 56
    static let posterWidth: CGFloat = 164
    static let posterHeight: CGFloat = 246

    enum Font {
        static func regular(_ size: CGFloat) -> NSFont { .systemFont(ofSize: size, weight: .regular) }
        static func medium(_ size: CGFloat) -> NSFont { .systemFont(ofSize: size, weight: .medium) }
        static func semibold(_ size: CGFloat) -> NSFont { .systemFont(ofSize: size, weight: .semibold) }
        static func bold(_ size: CGFloat) -> NSFont { .systemFont(ofSize: size, weight: .bold) }
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}

extension NSView {
    /// Make a view layer-backed with a solid fill and optional rounded corners.
    func fill(_ color: NSColor, corner: CGFloat = 0) {
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = corner
    }
}
