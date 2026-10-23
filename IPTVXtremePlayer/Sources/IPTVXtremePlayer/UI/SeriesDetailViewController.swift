import AppKit

/// Series detail: artwork, metadata, season picker, and an episode list with
/// per-episode playback and automatic next-episode advancement.
final class SeriesDetailViewController: VScrollController {
    private let series: SeriesStream
    private var info: SeriesInfo?
    private var selectedSeason: Int = 0
    private let seasonPopup = NSPopUpButton()
    private let favButton = IconButton(symbol: "star", pointSize: 16, tint: Theme.textSecondary, hover: Theme.accent)

    init(coordinator: AppCoordinator, series: SeriesStream) {
        self.series = series
        super.init(coordinator: coordinator)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidAppear() {
        super.viewDidAppear()
        if info == nil { load() }
    }

    private func load() {
        showLoading()
        Task { @MainActor in
            info = try? await coordinator.session.seriesInfo(series.seriesID)
            hideOverlay()
            selectedSeason = info?.sortedSeasons.first ?? 0
            build()
        }
    }

    private func build() {
        clearContent()

        let poster = AsyncImageView()
        poster.translatesAutoresizingMaskIntoConstraints = false
        poster.layer?.cornerRadius = Theme.corner
        poster.load(info?.cover ?? series.cover, placeholder: "rectangle.stack")
        poster.widthAnchor.constraint(equalToConstant: 230).isActive = true
        poster.heightAnchor.constraint(equalToConstant: 345).isActive = true

        let title = makeLabel(series.name, font: Theme.Font.bold(26), color: Theme.textPrimary, lines: 2)

        var metaParts: [String] = []
        if let d = info?.releaseDate ?? series.releaseDate, d.count >= 4 { metaParts.append(String(d.prefix(4))) }
        if let g = info?.genre ?? series.genre, !g.isEmpty { metaParts.append(g) }
        let seasonCount = info?.sortedSeasons.count ?? 0
        if seasonCount > 0 { metaParts.append("\(seasonCount) season\(seasonCount == 1 ? "" : "s")") }
        if let r = info?.rating, !r.isEmpty { metaParts.append("★ \(r)") }
        else if let r5 = series.rating5 { metaParts.append(String(format: "★ %.1f", r5)) }
        let meta = makeLabel(metaParts.joined(separator: "  ·  "), font: Theme.Font.medium(13), color: Theme.accent)

        updateFavIcon()
        favButton.target = self; favButton.action = #selector(toggleFavorite)
        let favLabel = makeLabel("Add to Favorites", font: Theme.Font.medium(12.5), color: Theme.textSecondary)
        let favStack = NSStackView(views: [favButton, favLabel])
        favStack.spacing = 8; favStack.alignment = .centerY

        let infoStack = NSStackView(views: [title, meta, favStack])
        infoStack.orientation = .vertical
        infoStack.spacing = 12
        infoStack.alignment = .leading

        if let plot = info?.plot ?? series.plot, !plot.isEmpty {
            let plotLabel = makeLabel(plot, font: Theme.Font.regular(13.5), color: Theme.textSecondary, lines: 0)
            infoStack.addArrangedSubview(plotLabel)
            plotLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 560).isActive = true
        }

        let header = NSStackView(views: [poster, infoStack])
        header.orientation = .horizontal
        header.spacing = 26
        header.alignment = .top
        addFullWidth(header)

        // Season picker + episodes
        guard let info = info, !info.sortedSeasons.isEmpty else {
            addFullWidth(makeLabel("No episodes are available for this series.",
                                   font: Theme.Font.regular(14), color: Theme.textTertiary))
            return
        }

        seasonPopup.removeAllItems()
        seasonPopup.addItems(withTitles: info.sortedSeasons.map { "Season \($0)" })
        if let idx = info.sortedSeasons.firstIndex(of: selectedSeason) { seasonPopup.selectItem(at: idx) }
        seasonPopup.target = self; seasonPopup.action = #selector(seasonChanged)
        seasonPopup.translatesAutoresizingMaskIntoConstraints = false
        seasonPopup.widthAnchor.constraint(equalToConstant: 160).isActive = true

        let episodesHeader = NSStackView(views: [makeLabel("Episodes", font: Theme.Font.semibold(18)), NSView(), seasonPopup])
        episodesHeader.alignment = .centerY
        addFullWidth(episodesHeader)

        let episodes = info.episodesBySeason[selectedSeason] ?? []
        let list = NSStackView()
        list.orientation = .vertical
        list.spacing = 8
        list.alignment = .leading
        for (idx, ep) in episodes.enumerated() {
            let row = makeEpisodeRow(ep, indexInSeason: idx, episodes: episodes)
            list.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }
        addFullWidth(list)
    }

    private func makeEpisodeRow(_ ep: Episode, indexInSeason: Int, episodes: [Episode]) -> NSView {
        let row = NSView()
        row.fill(Theme.surface, corner: 8)
        row.translatesAutoresizingMaskIntoConstraints = false

        let numView = makeLabel("\(ep.episodeNum)", font: Theme.Font.bold(15), color: Theme.accent, align: .center)
        numView.widthAnchor.constraint(equalToConstant: 34).isActive = true

        let title = makeLabel(ep.title.isEmpty ? "Episode \(ep.episodeNum)" : ep.title,
                              font: Theme.Font.medium(14), color: Theme.textPrimary, lines: 1)
        var sub = ""
        if let d = ep.durationSecs, d > 0 { sub = formatDuration(d) }
        if DownloadManager.shared.localFileURL(for: .episode(ep, series: series)) != nil {
            sub += sub.isEmpty ? "✓ Available offline" : "  ·  ✓ Available offline"
        }
        let subtitle = makeLabel(sub, font: Theme.Font.regular(11.5), color: Theme.textTertiary)
        let textStack = NSStackView(views: [title, subtitle])
        textStack.orientation = .vertical; textStack.spacing = 2; textStack.alignment = .leading

        let playIcon = IconButton(symbol: "play.circle.fill", pointSize: 24, tint: Theme.accent)
        playIcon.target = self
        playIcon.action = #selector(episodePlayTapped(_:))
        playIcon.tag = indexInSeason

        let content = NSStackView(views: [numView, textStack, NSView(), playIcon])
        content.alignment = .centerY
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(content)
        content.pinEdges(to: row, insets: NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12))

        let click = NSClickGestureRecognizer(target: self, action: #selector(episodeRowClicked(_:)))
        row.addGestureRecognizer(click)
        row.identifier = NSUserInterfaceItemIdentifier("\(indexInSeason)")
        return row
    }

    @objc private func episodeRowClicked(_ g: NSClickGestureRecognizer) {
        guard let id = g.view?.identifier?.rawValue, let idx = Int(id) else { return }
        playEpisode(atIndex: idx)
    }
    @objc private func episodePlayTapped(_ sender: IconButton) {
        playEpisode(atIndex: sender.tag)
    }

    private func playEpisode(atIndex index: Int) {
        guard let info = info,
              let episodes = info.episodesBySeason[selectedSeason], index < episodes.count else { return }
        // Navigator spans the whole series (all seasons) in order, positioned at
        // the chosen episode, so Prev/Next and auto-advance cross season boundaries.
        let navigator = EpisodeNavigator.forSeries(series, info: info, startingAt: episodes[index],
                                                   session: coordinator.session)
        guard let item = navigator.currentItem() else { return }
        coordinator.playInWindow(item, navigator: navigator)
    }

    @objc private func seasonChanged() {
        guard let seasons = info?.sortedSeasons, seasonPopup.indexOfSelectedItem < seasons.count else { return }
        selectedSeason = seasons[seasonPopup.indexOfSelectedItem]
        build()
    }

    @objc private func toggleFavorite() {
        _ = coordinator.session.userData.toggleFavorite(.series(series))
        updateFavIcon()
    }
    private func updateFavIcon() {
        let fav = coordinator.session.userData.isFavorite(.series(series))
        favButton.setSymbol(fav ? "star.fill" : "star", pointSize: 16)
        favButton.contentTintColor = fav ? Theme.accent : Theme.textSecondary
    }

    private func formatDuration(_ secs: Int) -> String {
        let h = secs / 3600, m = (secs % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
