import AppKit

func formatHMS(_ totalSeconds: Double) -> String {
    guard totalSeconds.isFinite, totalSeconds >= 0 else { return "0:00" }
    let s = Int(totalSeconds)
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
    return String(format: "%d:%02d", m, sec)
}

/// Borderless button showing an SF Symbol, tinted, with a subtle hover state.
final class IconButton: NSButton {
    private let baseTint: NSColor
    private let hoverTint: NSColor
    private var tracking: NSTrackingArea?

    init(symbol: String, pointSize: CGFloat = 15, weight: NSFont.Weight = .semibold,
         tint: NSColor = Theme.textPrimary, hover: NSColor = Theme.accent,
         accessibility: String = "") {
        baseTint = tint
        hoverTint = hover
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        imageScaling = .scaleProportionallyUpOrDown
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibility)?
            .withSymbolConfiguration(config)
        contentTintColor = tint
        wantsLayer = true
        setButtonType(.momentaryChange)
    }
    required init?(coder: NSCoder) { fatalError() }

    func setSymbol(_ symbol: String, pointSize: CGFloat = 15, weight: NSFont.Weight = .semibold) {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }
    override func mouseEntered(with event: NSEvent) { contentTintColor = hoverTint }
    override func mouseExited(with event: NSEvent) { contentTintColor = baseTint }
}

/// Vertical gradient layer-backed view (used behind player controls).
final class GradientView: NSView {
    var colors: [NSColor] = [.clear, NSColor.black.withAlphaComponent(0.85)] {
        didSet { applyColors() }
    }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CAGradientLayer()
        applyColors()
    }
    required init?(coder: NSCoder) { fatalError() }
    private func applyColors() {
        (layer as? CAGradientLayer)?.colors = colors.map { $0.cgColor }
    }
}

extension NSView {
    func pinEdges(to other: NSView, insets: NSEdgeInsets = NSEdgeInsets()) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -insets.right),
            topAnchor.constraint(equalTo: other.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -insets.bottom)
        ])
    }
}

func makeLabel(_ text: String = "", font: NSFont, color: NSColor = Theme.textPrimary,
               align: NSTextAlignment = .left, lines: Int = 1) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = font
    l.textColor = color
    l.alignment = align
    l.maximumNumberOfLines = lines
    l.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
    l.translatesAutoresizingMaskIntoConstraints = false
    return l
}
