import AppKit

/// Centered loading spinner with an optional caption.
final class LoadingView: NSView {
    private let spinner = NSProgressIndicator()
    private let label = makeLabel(font: Theme.Font.medium(13), color: Theme.textSecondary, align: .center)

    init(message: String = "Loading…") {
        super.init(frame: .zero)
        spinner.style = .spinning
        spinner.isIndeterminate = true
        spinner.appearance = NSAppearance(named: .darkAqua)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        label.stringValue = message
        addSubview(spinner)
        addSubview(label)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 12),
            label.centerXAnchor.constraint(equalTo: centerXAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func start() { isHidden = false; spinner.startAnimation(nil) }
    func stop() { isHidden = true; spinner.stopAnimation(nil) }
}

/// Centered empty / error state with icon, title, message, and optional action.
final class EmptyStateView: NSView {
    var onAction: (() -> Void)?

    init(symbol: String, title: String, message: String, actionTitle: String? = nil) {
        super.init(frame: .zero)
        let config = NSImage.SymbolConfiguration(pointSize: 44, weight: .regular)
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        icon.contentTintColor = Theme.textTertiary
        icon.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = makeLabel(title, font: Theme.Font.semibold(17), color: Theme.textPrimary, align: .center)
        let msgLabel = makeLabel(message, font: Theme.Font.regular(13.5), color: Theme.textSecondary, align: .center, lines: 4)

        let stack = NSStackView(views: [icon, titleLabel, msgLabel])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            msgLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 380)
        ])

        if let actionTitle = actionTitle {
            let button = PillButton(title: actionTitle)
            button.onClick = { [weak self] in self?.onAction?() }
            stack.addArrangedSubview(button)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Rounded accent button.
final class PillButton: NSView {
    var onClick: (() -> Void)?
    private let label: NSTextField

    init(title: String, filled: Bool = true) {
        label = makeLabel(title, font: Theme.Font.semibold(13),
                          color: filled ? .white : Theme.accent, align: .center)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.backgroundColor = (filled ? Theme.accent : NSColor.clear).cgColor
        if !filled { layer?.borderWidth = 1; layer?.borderColor = Theme.accent.cgColor }
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 38),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 130),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18)
        ])
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(tapped)))
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func tapped() { onClick?() }
}
