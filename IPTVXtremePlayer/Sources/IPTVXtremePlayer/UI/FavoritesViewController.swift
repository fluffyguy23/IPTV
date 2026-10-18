import AppKit

/// Favorites grouped into Channels, Movies, and Series rails.
final class FavoritesViewController: VScrollController, Refreshable {
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

        let channels = user.favorites(of: .live)
        if !channels.isEmpty {
            let cards = channels.map { ref -> PosterCard in
                let card = PosterCard(width: 150, posterHeight: 150, placeholder: "tv")
                card.configure(title: ref.title, subtitle: nil, posterURL: ref.poster, placeholder: "tv")
                card.onClick = { [weak self] in self?.coordinator.play(ref: ref) }
                self.attachFavMenu(card, ref: ref)
                return card
            }
            addFullWidth(Rail.make(title: "Favorite Channels", cards: cards))
            added = true
        }

        let movies = user.favorites(of: .movie)
        if !movies.isEmpty {
            let cards = movies.map { ref -> PosterCard in
                let card = PosterCard()
                card.configure(title: ref.title, subtitle: nil, posterURL: ref.poster, placeholder: "film")
                card.onClick = { [weak self] in self?.openMovie(ref) }
                self.attachFavMenu(card, ref: ref)
                return card
            }
            addFullWidth(Rail.make(title: "Favorite Movies", cards: cards))
            added = true
        }

        // Series favorites are stored with the episode kind + "series-" id.
        let series = user.favorites.filter { $0.episodeID?.hasPrefix("series-") == true }
        if !series.isEmpty {
            let cards = series.map { ref -> PosterCard in
                let card = PosterCard()
                card.configure(title: ref.title, subtitle: nil, posterURL: ref.poster, placeholder: "rectangle.stack")
                card.onClick = { [weak self] in self?.openSeries(ref) }
                self.attachFavMenu(card, ref: ref)
                return card
            }
            addFullWidth(Rail.make(title: "Favorite Series", cards: cards))
            added = true
        }

        if !added {
            showEmpty(symbol: "star", title: "No favorites yet",
                      message: "Tap the star on any channel, movie, or series to save it here.")
        } else {
            hideOverlay()
        }
    }

    private func openMovie(_ ref: MediaRef) {
        if let id = ref.streamID, let movie = coordinator.session.allMovies.first(where: { $0.streamID == id }) {
            coordinator.openMovie(movie)
        } else {
            coordinator.play(ref: ref)
        }
    }
    private func openSeries(_ ref: MediaRef) {
        if let sid = ref.seriesID, let show = coordinator.session.allSeries.first(where: { $0.seriesID == sid }) {
            coordinator.openSeries(show)
        }
    }

    private func attachFavMenu(_ card: PosterCard, ref: MediaRef) {
        card.menuProvider = { [weak self] in
            guard let self = self else { return nil }
            let menu = NSMenu()
            let remove = NSMenuItem(title: "Remove from Favorites", action: #selector(self.removeFav(_:)), keyEquivalent: "")
            remove.target = self; remove.representedObject = ref
            menu.addItem(remove)
            return menu
        }
    }

    @objc private func removeFav(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? MediaRef else { return }
        _ = coordinator.session.userData.toggleFavorite(ref)
        build()
    }
}
