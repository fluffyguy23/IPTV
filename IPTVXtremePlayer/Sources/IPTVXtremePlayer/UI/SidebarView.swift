import AppKit

/// Left navigation rail: brand, section rows, and a disconnect button.
final class SidebarView: NSView {
    var onSelect: ((Section) -> Void)?
    var onDisconnect: (() -> Void)?

    private var rows: [Section: SidebarRow] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        fill(Theme.sidebar)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        // Brand
        let brand = makeLabel("IPTV", font: Theme.Font.bold(20), color: Theme.textPrimary)
        let brandAccent = makeLabel("Xtreme", font: Theme.Font.bold(20), color: Theme.accent)
        let brandStack = NSStackView(views: [brand, brandAccent])
        brandStack.spacing = 0
        brandStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(brandStack)

        let subtitle = makeLabel("PLAYER", font: Theme.Font.semibold(9), color: Theme.textTertiary)
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitle)

        // Section rows
        let rowStack = NSStackView()
        rowStack.orientation = .vertical
        rowStack.spacing = 2
        rowStack.alignment = .leading
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowStack)

        for section in Section.allCases {
            let row = SidebarRow(section: section)
            row.onClick = { [weak self] in self?.onSelect?(section) }
            rows[section] = row
            rowStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rowStack.widthAnchor).isActive = true
        }

        // Disconnect
        let disconnect = SidebarRow(section: nil, title: "Disconnect", symbol: "rectangle.portrait.and.arrow.right", danger: true)
        disconnect.onClick = { [weak self] in self?.onDisconnect?() }
        disconnect.translatesAutoresizingMaskIntoConstraints = false
        addSubview(disconnect)

        NSLayoutConstraint.activate([
            brandStack.topAnchor.constraint(equalTo: topAnchor, constant: 30),
            brandStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            subtitle.topAnchor.constraint(equalTo: brandStack.bottomAnchor, constant: 1),
            subtitle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 21),

            rowStack.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 28),
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            rowStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            disconnect.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            disconnect.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            disconnect.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20)
        ])

        // Right divider
        let divider = NSView()
        divider.fill(Theme.border)
        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider)
        NSLayoutConstraint.activate([
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.topAnchor.constraint(equalTo: topAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1)
        ])
    }

    func setSelected(_ section: Section?) {
        for (sec, row) in rows { row.isSelected = (sec == section) }
    }
}

/// A single sidebar entry with hover and selected states.
final class SidebarRow: NSView {
    var onClick: (() -> Void)?
    private let iconView = NSImageView()
    private let label: NSTextField
    private let danger: Bool
    private var tracking: NSTrackingArea?

    var isSelected = false { didSet { restyle() } }
    private var isHovered = false { didSet { restyle() } }

    init(section: Section?, title: String? = nil, symbol: String? = nil, danger: Bool = false) {
        self.danger = danger
        let text = title ?? section?.title ?? ""
        label = makeLabel(text, font: Theme.Font.medium(13.5), color: Theme.textSecondary)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: symbol ?? section?.symbol ?? "circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        iconView.contentTintColor = Theme.textSecondary
        iconView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 40),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8)
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        addGestureRecognizer(click)
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func clicked() { onClick?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }
    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    private func restyle() {
        let accent = danger ? Theme.negative : Theme.accent
        if isSelected {
            layer?.backgroundColor = Theme.accentSoft.cgColor
            iconView.contentTintColor = accent
            label.textColor = Theme.textPrimary
        } else if isHovered {
            layer?.backgroundColor = Theme.surfaceHover.withAlphaComponent(0.6).cgColor
            iconView.contentTintColor = danger ? Theme.negative : Theme.textPrimary
            label.textColor = danger ? Theme.negative : Theme.textPrimary
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            iconView.contentTintColor = danger ? Theme.negative.withAlphaComponent(0.8) : Theme.textSecondary
            label.textColor = danger ? Theme.negative.withAlphaComponent(0.9) : Theme.textSecondary
        }
    }
}
