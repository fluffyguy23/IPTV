import AppKit

/// Reusable poster grid for Movies and Series, with category filtering,
/// in-section search, and sorting. Fetches per-category to keep payloads small.
final class MediaGridViewController: NSViewController, NSCollectionViewDataSource, Refreshable {
    enum Kind { case movies, series }

    private let coordinator: AppCoordinator
    private let kind: Kind

    private var categories: [Category] = []
    private var rawMovies: [VODStream] = []
    private var rawSeries: [SeriesStream] = []
    private var entries: [GridEntry] = []
    private var selectedCategoryID: String?
    private var sort: SortOrder = .defaultOrder
    private var filterText = ""

    private enum SortOrder { case defaultOrder, az, recent, rating }

    private let categoryPopup = NSPopUpButton()
    private let sortPopup = NSPopUpButton()
    private let filterField = NSSearchField()
    private let collectionView = NSCollectionView()
    private let scroll = NSScrollView()
    private let loading = LoadingView()
    private var emptyView: EmptyStateView?

    init(coordinator: AppCoordinator, kind: Kind) {
        self.coordinator = coordinator
        self.kind = kind
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView()
        view.fill(Theme.background)
        buildToolbar()
        buildCollection()
        buildOverlays()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if categories.isEmpty && rawMovies.isEmpty && rawSeries.isEmpty { loadCategories() }
    }

    // MARK: UI

    private func buildToolbar() {
        categoryPopup.target = self; categoryPopup.action = #selector(categoryChanged)
        sortPopup.target = self; sortPopup.action = #selector(sortChanged)
        sortPopup.addItems(withTitles: ["Default", "A–Z", "Recently Added", "Top Rated"])

        filterField.placeholderString = "Filter \(kind == .movies ? "movies" : "series")…"
        filterField.target = self; filterField.action = #selector(filterChanged)
        filterField.sendsSearchStringImmediately = true
        filterField.translatesAutoresizingMaskIntoConstraints = false

        for popup in [categoryPopup, sortPopup] {
            popup.translatesAutoresizingMaskIntoConstraints = false
            popup.bezelStyle = .rounded
        }

        let catLabel = makeLabel("Category", font: Theme.Font.medium(11), color: Theme.textTertiary)
        let sortLabel = makeLabel("Sort", font: Theme.Font.medium(11), color: Theme.textTertiary)
        let catStack = labeledControl(catLabel, categoryPopup)
        let sortStack = labeledControl(sortLabel, sortPopup)

        let bar = NSStackView(views: [catStack, sortStack, NSView(), filterField])
        bar.spacing = 16
        bar.alignment = .bottom
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            categoryPopup.widthAnchor.constraint(equalToConstant: 220),
            sortPopup.widthAnchor.constraint(equalToConstant: 160),
            filterField.widthAnchor.constraint(equalToConstant: 240),
            filterField.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    private func labeledControl(_ label: NSView, _ control: NSView) -> NSStackView {
        let s = NSStackView(views: [label, control])
        s.orientation = .vertical
        s.spacing = 4
        s.alignment = .leading
        return s
    }

    private func buildCollection() {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: Theme.posterWidth, height: Theme.posterHeight + 48)
        layout.minimumInteritemSpacing = 18
        layout.minimumLineSpacing = 24
        layout.sectionInset = NSEdgeInsets(top: 16, left: 28, bottom: 28, right: 28)

        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.isSelectable = false
        collectionView.backgroundColors = [.clear]
        collectionView.register(PosterItem.self, forItemWithIdentifier: PosterItem.identifier)

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.documentView = collectionView
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor, constant: 78),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func buildOverlays() {
        loading.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loading)
        NSLayoutConstraint.activate([
            loading.topAnchor.constraint(equalTo: scroll.topAnchor),
            loading.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            loading.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            loading.bottomAnchor.constraint(equalTo: scroll.bottomAnchor)
        ])
        loading.stop()
    }

    // MARK: Data

    private func loadCategories() {
        loading.start()
        Task { @MainActor in
            do {
                categories = try await (kind == .movies ? coordinator.session.movieCategories()
                                                         : coordinator.session.seriesCategories())
            } catch {
                categories = []
            }
            categoryPopup.removeAllItems()
            categoryPopup.addItem(withTitle: "All")
            categoryPopup.addItems(withTitles: categories.map { $0.name })
            loadItems(categoryID: nil)
        }
    }

    private func loadItems(categoryID: String?) {
        loading.start()
        setEmpty(nil)
        Task { @MainActor in
            do {
                if kind == .movies {
                    rawMovies = categoryID == nil
                        ? try await coordinator.session.loadAllMovies()
                        : try await coordinator.session.client.vodStreams(categoryID: categoryID)
                } else {
                    rawSeries = categoryID == nil
                        ? try await coordinator.session.loadAllSeries()
                        : try await coordinator.session.client.series(categoryID: categoryID)
                }
                loading.stop()
                recompute()
            } catch {
                loading.stop()
                setEmpty(EmptyStateView(symbol: "wifi.exclamationmark", title: "Couldn't load",
                                        message: (error as? XtreamError)?.errorDescription ?? "Please try again."))
            }
        }
    }

    private func recompute() {
        var items: [GridEntry] = []
        if kind == .movies {
            var list = rawMovies
            if !filterText.isEmpty { list = list.filter { $0.name.lowercased().contains(filterText) } }
            switch sort {
            case .defaultOrder: break
            case .az: list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            case .recent: list.sort { ($0.addedTimestamp ?? 0) > ($1.addedTimestamp ?? 0) }
            case .rating: list.sort { ($0.rating5 ?? 0) > ($1.rating5 ?? 0) }
            }
            items = list.map { movie in
                GridEntry(title: movie.name, subtitle: nil, poster: movie.icon, placeholder: "film",
                          badge: movie.rating5.map { String(format: "%.1f", $0) }) { [weak self] in
                    self?.coordinator.openMovie(movie)
                }
            }
        } else {
            var list = rawSeries
            if !filterText.isEmpty { list = list.filter { $0.name.lowercased().contains(filterText) } }
            switch sort {
            case .defaultOrder: break
            case .az: list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            case .recent: list.sort { ($0.lastModified ?? 0) > ($1.lastModified ?? 0) }
            case .rating: list.sort { ($0.rating5 ?? 0) > ($1.rating5 ?? 0) }
            }
            items = list.map { show in
                GridEntry(title: show.name, subtitle: nil, poster: show.cover, placeholder: "rectangle.stack",
                          badge: show.rating5.map { String(format: "%.1f", $0) }) { [weak self] in
                    self?.coordinator.openSeries(show)
                }
            }
        }
        entries = items
        collectionView.reloadData()
        if entries.isEmpty {
            setEmpty(EmptyStateView(symbol: "magnifyingglass", title: "No results",
                                    message: "Nothing matches the current filter."))
        } else {
            setEmpty(nil)
        }
    }

    private func setEmpty(_ v: EmptyStateView?) {
        emptyView?.removeFromSuperview()
        emptyView = v
        guard let v = v else { return }
        v.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: scroll.topAnchor),
            v.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            v.bottomAnchor.constraint(equalTo: scroll.bottomAnchor)
        ])
    }

    func refresh() {
        loadItems(categoryID: selectedCategoryID)
    }

    // MARK: Actions

    @objc private func categoryChanged() {
        let idx = categoryPopup.indexOfSelectedItem
        selectedCategoryID = idx <= 0 ? nil : categories[idx - 1].id
        loadItems(categoryID: selectedCategoryID)
    }
    @objc private func sortChanged() {
        sort = [.defaultOrder, .az, .recent, .rating][sortPopup.indexOfSelectedItem]
        recompute()
    }
    @objc private func filterChanged() {
        filterText = filterField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        recompute()
    }

    // MARK: Data source

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        entries.count
    }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: PosterItem.identifier, for: indexPath) as! PosterItem
        item.configure(entries[indexPath.item])
        return item
    }
}
