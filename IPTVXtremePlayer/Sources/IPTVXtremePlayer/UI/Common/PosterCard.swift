import AppKit

/// A poster tile: artwork, title, subtitle, optional resume-progress bar, and a
/// hover lift. Used in rails, grids, and search results.
final class PosterCard: NSView {
    var onClick: (() -> Void)?
    /// Right-click context menu (e.g. "Remove from History").
    var menuProvider: (() -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?() ?? super.menu(for: event)
    }

    private let poster = AsyncImageView()
    private let titleLabel = makeLabel(font: Theme.Font.semibold(12.5), color: Theme.textPrimary, lines: 1)
    private let subtitleLabel = makeLabel(font: Theme.Font.regular(11), color: Theme.textTertiary, lines: 1)
    private let progressTrack = NSView()
    private let progressFill = NSView()
    private let badge = makeLabel(font: Theme.Font.bold(10), color: .white, align: .center)
    private var tracking: NSTrackingArea?
    private var progressWidth: NSLayoutConstraint?

    init(width: CGFloat = Theme.posterWidth, posterHeight: CGFloat = Theme.posterHeight,
         placeholder: String = "film") {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        poster.translatesAutoresizingMaskIntoConstraints = false
        poster.layer?.cornerRadius = Theme.corner
        poster.shadow = NSShadow()
        poster.layer?.shadowColor = NSColor.black.cgColor
        poster.layer?.shadowOpacity = 0.4
        poster.layer?.shadowRadius = 8
        poster.layer?.shadowOffset = CGSize(width: 0, height: -3)
        addSubview(poster)

        // Resume progress
        progressTrack.fill(NSColor.black.withAlphaComponent(0.55))
        progressTrack.wantsLayer = true
        progressTrack.layer?.cornerRadius = 1.5
        progressTrack.translatesAutoresizingMaskIntoConstraints = false
        progressFill.fill(Theme.accent)
        progressFill.layer?.cornerRadius = 1.5
        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.addSubview(progressFill)
        poster.addSubview(progressTrack)
        progressTrack.isHidden = true

        // Badge (e.g. rating)
        badge.wantsLayer = true
        badge.layer?.backgroundColor = Theme.accent.cgColor
        badge.layer?.cornerRadius = 5
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.isHidden = true
        poster.addSubview(badge)

        addSubview(titleLabel)
        addSubview(subtitleLabel)
        poster.load(nil, placeholder: placeholder)

        progressWidth = progressFill.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            poster.topAnchor.constraint(equalTo: topAnchor),
            poster.leadingAnchor.constraint(equalTo: leadingAnchor),
            poster.trailingAnchor.constraint(equalTo: trailingAnchor),
            poster.heightAnchor.constraint(equalToConstant: posterHeight),

            progressTrack.leadingAnchor.constraint(equalTo: poster.leadingAnchor, constant: 8),
            progressTrack.trailingAnchor.constraint(equalTo: poster.trailingAnchor, constant: -8),
            progressTrack.bottomAnchor.constraint(equalTo: poster.bottomAnchor, constant: -8),
            progressTrack.heightAnchor.constraint(equalToConstant: 3),
            progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressFill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            progressWidth!,

            badge.topAnchor.constraint(equalTo: poster.topAnchor, constant: 8),
            badge.trailingAnchor.constraint(equalTo: poster.trailingAnchor, constant: -8),
            badge.heightAnchor.constraint(equalToConstant: 18),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 30),

            titleLabel.topAnchor.constraint(equalTo: poster.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(tapped)))
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, subtitle: String?, posterURL: String?,
                   placeholder: String = "film", progress: Double? = nil, badgeText: String? = nil) {
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle ?? ""
        subtitleLabel.isHidden = (subtitle == nil)
        poster.load(posterURL, placeholder: placeholder)

        if let progress = progress, progress > 0.01 {
            progressTrack.isHidden = false
            layoutSubtreeIfNeeded()
            let trackWidth = progressTrack.bounds.width
            progressWidth?.constant = max(4, trackWidth * CGFloat(min(1, progress)))
        } else {
            progressTrack.isHidden = true
            progressWidth?.constant = 0
        }

        if let badgeText = badgeText, !badgeText.isEmpty {
            badge.isHidden = false
            badge.stringValue = " \(badgeText) "
        } else {
            badge.isHidden = true
        }
    }

    @objc private func tapped() { onClick?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }
    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            poster.animator().layer?.borderWidth = 2
            poster.layer?.borderColor = Theme.accent.cgColor
        }
    }
    override func mouseExited(with event: NSEvent) {
        poster.layer?.borderWidth = 0
    }
}
