import AppKit

/// Movie detail: artwork, metadata, plot, and play / resume / favorite actions.
final class VODDetailViewController: VScrollController {
    private let movie: VODStream
    private var info: VODInfo?
    private let favButton = IconButton(symbol: "star", pointSize: 16, tint: Theme.textSecondary, hover: Theme.accent)

    init(coordinator: AppCoordinator, movie: VODStream) {
        self.movie = movie
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
            info = try? await coordinator.session.vodInfo(movie.streamID)
            hideOverlay()
            build()
        }
    }

    private func build() {
        clearContent()

        let poster = AsyncImageView()
        poster.translatesAutoresizingMaskIntoConstraints = false
        poster.layer?.cornerRadius = Theme.corner
        poster.load(info?.posterPath ?? movie.icon, placeholder: "film")
        poster.widthAnchor.constraint(equalToConstant: 230).isActive = true
        poster.heightAnchor.constraint(equalToConstant: 345).isActive = true

        let title = makeLabel(info?.name ?? movie.name, font: Theme.Font.bold(26), color: Theme.textPrimary, lines: 2)

        var metaParts: [String] = []
        if let d = info?.releaseDate, d.count >= 4 { metaParts.append(String(d.prefix(4))) }
        if let g = info?.genre, !g.isEmpty { metaParts.append(g) }
        if let secs = info?.durationSecs, secs > 0 { metaParts.append(formatDuration(secs)) }
        if let r = info?.rating, !r.isEmpty { metaParts.append("★ \(r)") }
        else if let r5 = movie.rating5 { metaParts.append(String(format: "★ %.1f", r5)) }
        let meta = makeLabel(metaParts.joined(separator: "  ·  "), font: Theme.Font.medium(13), color: Theme.accent)

        // Actions
        let resume = coordinator.session.userData.resumePosition(for: .movie(movie))
        let playButton = PillButton(title: resume > 10 ? "Resume" : "Play")
        playButton.onClick = { [weak self] in self?.play(resume: resume > 10) }
        var actionViews: [NSView] = [playButton]
        if resume > 10 {
            let restart = PillButton(title: "Play from Start", filled: false)
            restart.onClick = { [weak self] in self?.play(resume: false) }
            actionViews.append(restart)
        }
        updateFavIcon()
        favButton.target = self; favButton.action = #selector(toggleFavorite)
        actionViews.append(favButton)
        let actions = NSStackView(views: actionViews)
        actions.spacing = 12
        actions.alignment = .centerY

        let infoStack = NSStackView(views: [title, meta, actions])
        infoStack.orientation = .vertical
        infoStack.spacing = 14
        infoStack.alignment = .leading
        infoStack.setCustomSpacing(18, after: meta)

        let header = NSStackView(views: [poster, infoStack])
        header.orientation = .horizontal
        header.spacing = 26
        header.alignment = .top
        header.translatesAutoresizingMaskIntoConstraints = false
        addFullWidth(header)

        // Plot
        if let plot = info?.plot, !plot.isEmpty {
            addFullWidth(sectionTitle("Overview"))
            addFullWidth(makeLabel(plot, font: Theme.Font.regular(14), color: Theme.textSecondary, lines: 0))
        }
        // Cast / director
        if let cast = info?.cast, !cast.isEmpty {
            addFullWidth(keyValue("Cast", cast))
        }
        if let director = info?.director, !director.isEmpty {
            addFullWidth(keyValue("Director", director))
        }
    }

    private func play(resume: Bool) {
        guard var playable = coordinator.session.makeMovieItem(movie, ext: info?.containerExtension) else {
            errorAlert(); return
        }
        if !resume {
            playable = PlaybackItem(ref: playable.ref, url: playable.url, title: playable.title,
                                    isLive: false, resumeSecs: 0, networkCaching: 3000)
        }
        coordinator.playInWindow(playable, navigator: nil)
    }

    private func errorAlert() {
        let a = NSAlert(); a.messageText = "Unable to play this movie."; a.runModal()
    }

    @objc private func toggleFavorite() {
        _ = coordinator.session.userData.toggleFavorite(.movie(movie))
        updateFavIcon()
    }
    private func updateFavIcon() {
        let fav = coordinator.session.userData.isFavorite(.movie(movie))
        favButton.setSymbol(fav ? "star.fill" : "star", pointSize: 16)
        favButton.contentTintColor = fav ? Theme.accent : Theme.textSecondary
    }

    private func sectionTitle(_ t: String) -> NSView {
        makeLabel(t, font: Theme.Font.semibold(17), color: Theme.textPrimary)
    }
    private func keyValue(_ key: String, _ value: String) -> NSView {
        let k = makeLabel(key, font: Theme.Font.semibold(13), color: Theme.textTertiary)
        let v = makeLabel(value, font: Theme.Font.regular(13.5), color: Theme.textSecondary, lines: 0)
        let s = NSStackView(views: [k, v])
        s.orientation = .vertical; s.spacing = 3; s.alignment = .leading
        return s
    }
    private func formatDuration(_ secs: Int) -> String {
        let h = secs / 3600, m = (secs % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
