import AppKit

/// Global search across channels, movies, and series, shown as rails.
final class SearchViewController: VScrollController {
    private var query: String
    private let searchField = NSSearchField()
    private var didWarm = false

    init(coordinator: AppCoordinator, query: String) {
        self.query = query
        super.init(coordinator: coordinator)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidAppear() {
        super.viewDidAppear()
        ensureIndexAndSearch()
    }

    private func ensureIndexAndSearch() {
        let session = coordinator.session
        let hasIndex = !session.allLive.isEmpty || !session.allMovies.isEmpty || !session.allSeries.isEmpty
        if hasIndex {
            runSearch()
            return
        }
        showLoading("Preparing search…")
        Task { @MainActor in
            async let l = session.loadAllLive()
            async let m = session.loadAllMovies()
            async let s = session.loadAllSeries()
            _ = try? await l
            _ = try? await m
            _ = try? await s
            didWarm = true
            runSearch()
        }
    }

    private func runSearch() {
        clearContent()
        hideOverlay()

        // Refine field
        searchField.stringValue = query
        searchField.placeholderString = "Search…"
        searchField.target = self
        searchField.action = #selector(refine)
        searchField.sendsSearchStringImmediately = false
        searchField.translatesAutoresizingMaskIntoConstraints = false
        let header = makeLabel("Results for “\(query)”", font: Theme.Font.bold(22))
        let headerRow = NSStackView(views: [header, NSView(), searchField])
        headerRow.alignment = .centerY
        searchField.widthAnchor.constraint(equalToConstant: 260).isActive = true
        addFullWidth(headerRow)

        let results = coordinator.session.search(query)
        if results.isEmpty {
            showEmpty(symbol: "magnifyingglass", title: "No matches",
                      message: "No channels, movies, or series match “\(query)”.")
            return
        }

        if !results.live.isEmpty {
            let cards = results.live.map { channel -> PosterCard in
                let card = PosterCard(width: 150, posterHeight: 150, placeholder: "tv")
                card.configure(title: channel.name, subtitle: nil, posterURL: channel.icon, placeholder: "tv")
                card.onClick = { [weak self] in self?.coordinator.play(ref: .live(channel)) }
                return card
            }
            addFullWidth(Rail.make(title: "Channels", cards: cards))
        }
        if !results.movies.isEmpty {
            let cards = results.movies.map { movie -> PosterCard in
                let card = PosterCard()
                card.configure(title: movie.name, subtitle: nil, posterURL: movie.icon, placeholder: "film")
                card.onClick = { [weak self] in self?.coordinator.openMovie(movie) }
                return card
            }
            addFullWidth(Rail.make(title: "Movies", cards: cards))
        }
        if !results.series.isEmpty {
            let cards = results.series.map { show -> PosterCard in
                let card = PosterCard()
                card.configure(title: show.name, subtitle: nil, posterURL: show.cover, placeholder: "rectangle.stack")
                card.onClick = { [weak self] in self?.coordinator.openSeries(show) }
                return card
            }
            addFullWidth(Rail.make(title: "Series", cards: cards))
        }
    }

    @objc private func refine() {
        let q = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        query = q
        runSearch()
    }
}
