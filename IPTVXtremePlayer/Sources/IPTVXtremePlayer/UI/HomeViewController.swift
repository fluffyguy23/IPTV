import AppKit

/// Dashboard: Continue Watching, Recent Channels, Favorites, and freshly-added
/// Movies and Series. Each rail is skipped when empty.
final class HomeViewController: VScrollController, Refreshable {
    private var loaded = false

    override func viewDidAppear() {
        super.viewDidAppear()
        if !loaded { loaded = true; reload(force: false) }
        else { rebuildLocalRails() } // refresh resume/favorites which may have changed
    }

    func refresh() { reload(force: true) }

    private func reload(force: Bool) {
        showLoading()
        Task { @MainActor in
            async let movies = try? coordinator.session.loadAllMovies(forceRefresh: force)
            async let series = try? coordinator.session.loadAllSeries(forceRefresh: force)
            async let live = try? coordinator.session.loadAllLive(forceRefresh: force)
            _ = await (movies, series, live)
            hideOverlay()
            build()
        }
    }

    private func rebuildLocalRails() {
        guard loaded else { return }
        build()
    }

    private func build() {
        clearContent()
        let session = coordinator.session
        let user = session.userData
        var added = false

        // Continue watching
        let resume = user.continueWatching()
        if !resume.isEmpty {
            let cards = resume.map { entry -> PosterCard in
                let card = PosterCard()
                card.configure(title: entry.ref.title, subtitle: "Resume",
                               posterURL: entry.ref.poster,
                               placeholder: entry.ref.kind == .live ? "tv" : "film",
                               progress: entry.progressFraction)
                card.onClick = { [weak self] in self?.coordinator.play(ref: entry.ref) }
                return card
            }
            addFullWidth(Rail.make(title: "Continue Watching", cards: cards))
            added = true
        }

        // Recent channels
        let recentIDs = user.recentChannelIDs
        let liveByID = Dictionary(uniqueKeysWithValues: session.allLive.map { ($0.streamID, $0) })
        let recentChannels = recentIDs.compactMap { liveByID[$0] }
        if !recentChannels.isEmpty {
            let cards = recentChannels.prefix(12).map { channel -> PosterCard in
                let card = PosterCard(width: 150, posterHeight: 150, placeholder: "tv")
                card.configure(title: channel.name, subtitle: nil, posterURL: channel.icon, placeholder: "tv")
                card.onClick = { [weak self] in self?.coordinator.play(ref: .live(channel)) }
                return card
            }
            addFullWidth(Rail.make(title: "Recent Channels", cards: Array(cards)))
            added = true
        }

        // Favorites (movies + series)
        let favCards = user.favorites.prefix(14).map { ref -> PosterCard in
            let card = PosterCard(placeholder: ref.kind == .live ? "tv" : "film")
            card.configure(title: ref.title, subtitle: nil, posterURL: ref.poster,
                           placeholder: ref.kind == .live ? "tv" : "film")
            card.onClick = { [weak self] in self?.openFavorite(ref) }
            return card
        }
        if !favCards.isEmpty {
            addFullWidth(Rail.make(title: "Your Favorites", cards: Array(favCards)))
            added = true
        }

        // Recently added movies
        let newMovies = session.allMovies.sorted { ($0.addedTimestamp ?? 0) > ($1.addedTimestamp ?? 0) }.prefix(16)
        if !newMovies.isEmpty {
            let cards = newMovies.map { movie -> PosterCard in
                let card = PosterCard()
                card.configure(title: movie.name, subtitle: nil, posterURL: movie.icon, placeholder: "film",
                               badgeText: movie.rating5.map { String(format: "%.1f", $0) })
                card.onClick = { [weak self] in self?.coordinator.openMovie(movie) }
                return card
            }
            addFullWidth(Rail.make(title: "Recently Added Movies", cards: Array(cards)))
            added = true
        }

        // Recently added series
        let newSeries = session.allSeries.sorted { ($0.lastModified ?? 0) > ($1.lastModified ?? 0) }.prefix(16)
        if !newSeries.isEmpty {
            let cards = newSeries.map { show -> PosterCard in
                let card = PosterCard()
                card.configure(title: show.name, subtitle: nil, posterURL: show.cover, placeholder: "rectangle.stack",
                               badgeText: show.rating5.map { String(format: "%.1f", $0) })
                card.onClick = { [weak self] in self?.coordinator.openSeries(show) }
                return card
            }
            addFullWidth(Rail.make(title: "Recently Added Series", cards: Array(cards)))
            added = true
        }

        if !added {
            showEmpty(symbol: "sparkles.tv", title: "Nothing here yet",
                      message: "Browse Live TV, Movies, or Series to start watching. Your favorites and history will appear here.")
        }
    }

    private func openFavorite(_ ref: MediaRef) {
        switch ref.kind {
        case .live, .movie:
            coordinator.play(ref: ref)
        case .episode:
            // Series-level favorite: open the series detail if we can resolve it.
            if let sid = ref.seriesID, let show = coordinator.session.allSeries.first(where: { $0.seriesID == sid }) {
                coordinator.openSeries(show)
            } else {
                coordinator.play(ref: ref)
            }
        }
    }
}
