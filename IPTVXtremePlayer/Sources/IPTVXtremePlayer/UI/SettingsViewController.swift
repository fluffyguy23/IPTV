import AppKit

/// Account info, playback defaults, storage controls, and about.
final class SettingsViewController: VScrollController, Refreshable {
    override func viewDidAppear() {
        super.viewDidAppear()
        build()
    }

    func refresh() { build() }

    private func build() {
        clearContent()
        let session = coordinator.session
        let user = session.auth.userInfo

        // Account
        var account: [(String, String)] = [
            ("Profile", session.profile.name),
            ("Server", URL(string: session.profile.baseURL)?.host ?? session.profile.baseURL),
            ("Username", session.profile.username)
        ]
        if let status = user?.status { account.append(("Status", status)) }
        if let exp = user?.expDate {
            let df = DateFormatter(); df.dateStyle = .medium
            let remaining = Calendar.current.dateComponents([.day], from: Date(), to: exp).day ?? 0
            account.append(("Expires", "\(df.string(from: exp))  (\(max(0, remaining)) days)"))
        } else if user?.expDate == nil {
            account.append(("Expires", "Unlimited / not provided"))
        }
        if let active = user?.activeConnections, let max = user?.maxConnections {
            account.append(("Connections", "\(active) / \(max) active"))
        }
        if let formats = user?.allowedOutputFormats, !formats.isEmpty {
            account.append(("Output Formats", formats.joined(separator: ", ")))
        }
        addFullWidth(infoCard(title: "Account", rows: account))

        // Playback
        addFullWidth(infoCard(title: "Playback", rows: [
            ("Live Stream Format", session.profile.liveFormat.uppercased()),
            ("Playback Engine", "libVLC \(VLCPlayer.version)")
        ]))

        // Storage
        let storageCard = cardContainer(title: "Storage")
        let clearImages = PillButton(title: "Clear Image Cache", filled: false)
        clearImages.onClick = { Task { await ImageCache.shared.clearDisk() } }
        let clearData = PillButton(title: "Clear Content Cache", filled: false)
        clearData.onClick = { [weak self] in self?.coordinator.session.clearCaches() }
        let row = NSStackView(views: [clearImages, clearData])
        row.spacing = 12
        appendToCard(storageCard, view: row)
        addFullWidth(storageCard)

        // About
        addFullWidth(infoCard(title: "About", rows: [
            ("Application", "IPTVXtremePlayer 1.0"),
            ("Platform", "macOS · Intel x86_64")
        ]))

        // Disconnect / manage profiles
        let disconnect = PillButton(title: "Disconnect & Manage Profiles", filled: false)
        disconnect.onClick = { AppState.shared.disconnect() }
        addFullWidth(disconnect)

        hideOverlay()
    }

    // MARK: Card builders

    private func infoCard(title: String, rows: [(String, String)]) -> NSView {
        let card = cardContainer(title: title)
        for (k, v) in rows {
            let key = makeLabel(k, font: Theme.Font.medium(13), color: Theme.textTertiary)
            key.widthAnchor.constraint(equalToConstant: 160).isActive = true
            let value = makeLabel(v, font: Theme.Font.medium(13.5), color: Theme.textPrimary, lines: 2)
            let rowStack = NSStackView(views: [key, value])
            rowStack.alignment = .top
            rowStack.spacing = 12
            appendToCard(card, view: rowStack)
        }
        return card
    }

    private func cardContainer(title: String) -> NSView {
        let box = NSView()
        box.fill(Theme.surface, corner: 14)
        box.wantsLayer = true
        box.layer?.borderWidth = 1
        box.layer?.borderColor = Theme.border.cgColor
        box.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.identifier = NSUserInterfaceItemIdentifier("cardStack")
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(makeLabel(title, font: Theme.Font.semibold(16)))
        box.addSubview(stack)
        stack.pinEdges(to: box, insets: NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20))
        return box
    }

    private func appendToCard(_ card: NSView, view: NSView) {
        guard let stack = card.subviews.first(where: { $0.identifier?.rawValue == "cardStack" }) as? NSStackView else { return }
        stack.addArrangedSubview(view)
    }
}
