import AppKit

/// Top bar: back button, section/detail title, global search, profile status,
/// and refresh.
final class TopBarView: NSView {
    weak var coordinator: AppCoordinator?
    var onBack: (() -> Void)?

    private let backButton = IconButton(symbol: "chevron.left", pointSize: 14)
    private let titleLabel = makeLabel(font: Theme.Font.semibold(18))
    private let searchField = NSSearchField()
    private let profileLabel = makeLabel(font: Theme.Font.medium(12.5), color: Theme.textSecondary)
    private let statusDot = NSView()
    private let refreshButton = IconButton(symbol: "arrow.clockwise", pointSize: 14)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        fill(Theme.background)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        backButton.target = self; backButton.action = #selector(backTapped)
        backButton.isHidden = true
        refreshButton.target = self; refreshButton.action = #selector(refreshTapped)

        searchField.placeholderString = "Search channels, movies, series…"
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.target = self
        searchField.action = #selector(searchSubmitted)
        searchField.sendsSearchStringImmediately = false
        searchField.sendsWholeSearchString = true
        searchField.focusRingType = .none
        if let cell = searchField.cell as? NSSearchFieldCell {
            cell.cancelButtonCell?.target = self
        }
        styleSearch()

        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4

        let profilePill = NSStackView(views: [statusDot, profileLabel])
        profilePill.spacing = 7
        profilePill.alignment = .centerY
        profilePill.edgeInsets = NSEdgeInsets(top: 5, left: 12, bottom: 5, right: 12)
        profilePill.wantsLayer = true
        profilePill.layer?.backgroundColor = Theme.surface.cgColor
        profilePill.layer?.cornerRadius = 14
        profilePill.translatesAutoresizingMaskIntoConstraints = false

        let leftStack = NSStackView(views: [backButton, titleLabel])
        leftStack.spacing = 10
        leftStack.alignment = .centerY
        leftStack.translatesAutoresizingMaskIntoConstraints = false

        let rightStack = NSStackView(views: [searchField, profilePill, refreshButton])
        rightStack.spacing = 14
        rightStack.alignment = .centerY
        rightStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(leftStack)
        addSubview(rightStack)

        let divider = NSView()
        divider.fill(Theme.border)
        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider)

        NSLayoutConstraint.activate([
            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            leftStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 22),

            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            rightStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 300),
            searchField.heightAnchor.constraint(equalToConstant: 30),
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),

            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    private func styleSearch() {
        searchField.wantsLayer = true
        searchField.drawsBackground = false
        searchField.isBezeled = false
        searchField.textColor = Theme.textPrimary
        searchField.font = Theme.Font.regular(13)
        searchField.layer?.backgroundColor = Theme.surface.cgColor
        searchField.layer?.cornerRadius = 15
        searchField.layer?.borderWidth = 1
        searchField.layer?.borderColor = Theme.border.cgColor
    }

    func configure(profileName: String, status: String?) {
        profileLabel.stringValue = profileName
        let color: NSColor
        switch (status ?? "").lowercased() {
        case "active": color = Theme.positive
        case "expired", "banned", "disabled": color = Theme.negative
        default: color = Theme.warning
        }
        statusDot.layer?.backgroundColor = color.cgColor
    }

    func setBackVisible(_ visible: Bool) { backButton.isHidden = !visible }
    func setTitle(_ title: String) { titleLabel.stringValue = title }

    @objc private func backTapped() { onBack?() }
    @objc private func refreshTapped() {
        refreshButton.isEnabled = false
        coordinator?.refreshCurrentProfile()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.refreshButton.isEnabled = true }
    }
    @objc private func searchSubmitted() {
        coordinator?.performSearch(searchField.stringValue)
    }
}
