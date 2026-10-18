import AppKit

/// Recently Watched: resume rail, recent channels, and full history. Each item
/// has a right-click "Remove from History"; a toolbar button clears everything.
final class RecentViewController: VScrollController, Refreshable {
    override func viewDidAppear() {
        super.viewDidAppear()
        build()
    }

    func refresh() { build() }

    private func build() {
        clearContent()
        let session = coordinator.session
        let user = session.userData
        var added = false

        // Header with clear button
        let titleLabel = makeLabel("Recently Watched", font: Theme.Font.bold(22))
        let clear = PillButton(title: "Clear History", filled: false)
        clear.onClick = { [weak self] in self?.clearHistory() }
        let headerRow = NSStackView(views: [titleLabel, NSView(), clear])
        headerRow.alignment = .centerY
        addFullWidth(headerRow)

        let resume = user.continueWatching()
        if !resume.isEmpty {
            let cards = resume.map { entry -> PosterCard in
                let card = PosterCard(placeholder: entry.ref.kind == .live ? "tv" : "film")
                card.configure(title: entry.ref.title, subtitle: "Resume", posterURL: entry.ref.poster,
                               placeholder: entry.ref.kind == .live ? "tv" : "film", progress: entry.progressFraction)
                card.onClick = { [weak self] in self?.coordinator.play(ref: entry.ref) }
                self.attachMenu(card, ref: entry.ref)
                return card
            }
            addFullWidth(Rail.make(title: "Continue Watching", cards: cards))
            added = true
        }

        let liveByID = Dictionary(uniqueKeysWithValues: session.allLive.map { ($0.streamID, $0) })
        let recentChannels = user.recentChannelIDs.compactMap { liveByID[$0] }
        if !recentChannels.isEmpty {
            let cards = recentChannels.prefix(16).map { channel -> PosterCard in
                let card = PosterCard(width: 150, posterHeight: 150, placeholder: "tv")
                card.configure(title: channel.name, subtitle: nil, posterURL: channel.icon, placeholder: "tv")
                card.onClick = { [weak self] in self?.coordinator.play(ref: .live(channel)) }
                self.attachMenu(card, ref: .live(channel))
                return card
            }
            addFullWidth(Rail.make(title: "Recent Channels", cards: Array(cards)))
            added = true
        }

        // Full history (movies & episodes)
        let vodHistory = user.history.filter { $0.ref.isResumable }.prefix(24)
        if !vodHistory.isEmpty {
            let cards = vodHistory.map { entry -> PosterCard in
                let card = PosterCard()
                card.configure(title: entry.ref.title, subtitle: entry.isFinished ? "Watched" : nil,
                               posterURL: entry.ref.poster, placeholder: "film",
                               progress: entry.isFinished ? nil : entry.progressFraction)
                card.onClick = { [weak self] in self?.coordinator.play(ref: entry.ref) }
                self.attachMenu(card, ref: entry.ref)
                return card
            }
            addFullWidth(Rail.make(title: "History", cards: Array(cards)))
            added = true
        }

        if !added {
            showEmpty(symbol: "clock", title: "Nothing watched yet",
                      message: "Channels and titles you play will show up here so you can pick up where you left off. Right-click any item to remove it.")
        } else {
            hideOverlay()
        }
    }

    private func attachMenu(_ card: PosterCard, ref: MediaRef) {
        card.menuProvider = { [weak self] in
            guard let self = self else { return nil }
            let menu = NSMenu()
            let play = NSMenuItem(title: "Play", action: #selector(self.playFromMenu(_:)), keyEquivalent: "")
            play.target = self; play.representedObject = ref
            let remove = NSMenuItem(title: "Remove from History", action: #selector(self.removeFromMenu(_:)), keyEquivalent: "")
            remove.target = self; remove.representedObject = ref
            menu.addItem(play)
            menu.addItem(.separator())
            menu.addItem(remove)
            return menu
        }
    }

    @objc private func playFromMenu(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? MediaRef else { return }
        coordinator.play(ref: ref)
    }

    @objc private func removeFromMenu(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? MediaRef else { return }
        coordinator.session.userData.removeHistory(ref)
        build()
    }

    private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear watch history?"
        alert.informativeText = "This removes resume points and recent channels for this profile. Favorites and settings are not affected."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            coordinator.session.userData.clearHistory()
            build()
        }
    }
}
