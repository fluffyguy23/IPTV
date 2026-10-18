import AppKit

/// Live TV: category + channel list on the left, embedded player and EPG on the
/// right. Fast channel switching reuses one player instance.
final class LiveTVViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, Refreshable {
    private let coordinator: AppCoordinator

    private var categories: [Category] = []
    private var channels: [LiveStream] = []       // current category
    private var filtered: [LiveStream] = []
    private var selectedCategoryID: String?
    private var showingFavorites = false
    private var filterText = ""
    private var currentChannel: LiveStream?

    private let categoryPopup = NSPopUpButton()
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let tableScroll = NSScrollView()
    private let loading = LoadingView()

    private let playerContainer = NSView()
    private var playerVC: PlayerViewController?
    private let placeholder = EmptyStateView(symbol: "tv", title: "Select a channel",
                                             message: "Choose a channel from the list to start watching.")
    private let channelTitle = makeLabel(font: Theme.Font.semibold(16))
    private let epgNow = makeLabel(font: Theme.Font.medium(13), color: Theme.accent, lines: 1)
    private let epgNext = makeLabel(font: Theme.Font.regular(12), color: Theme.textTertiary, lines: 1)
    private let favButton = IconButton(symbol: "star", pointSize: 16, tint: Theme.textSecondary, hover: Theme.accent)

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView()
        view.fill(Theme.background)
        buildLayout()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if categories.isEmpty { loadCategories() }
    }

    // MARK: Layout

    private func buildLayout() {
        let leftPanel = NSView()
        leftPanel.fill(Theme.sidebar)
        leftPanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(leftPanel)

        categoryPopup.target = self; categoryPopup.action = #selector(categoryChanged)
        categoryPopup.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = "Search channels…"
        searchField.target = self; searchField.action = #selector(filterChanged)
        searchField.sendsSearchStringImmediately = true
        searchField.translatesAutoresizingMaskIntoConstraints = false

        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 54
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ch"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)

        tableScroll.documentView = tableView
        tableScroll.drawsBackground = false
        tableScroll.hasVerticalScroller = true
        tableScroll.translatesAutoresizingMaskIntoConstraints = false

        leftPanel.addSubview(categoryPopup)
        leftPanel.addSubview(searchField)
        leftPanel.addSubview(tableScroll)

        // Right panel
        let rightPanel = NSView()
        rightPanel.fill(Theme.background)
        rightPanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rightPanel)

        playerContainer.fill(.black)
        playerContainer.translatesAutoresizingMaskIntoConstraints = false
        rightPanel.addSubview(playerContainer)

        placeholder.translatesAutoresizingMaskIntoConstraints = false
        playerContainer.addSubview(placeholder)
        placeholder.pinEdges(to: playerContainer)

        // Info bar
        let infoBar = NSView()
        infoBar.fill(Theme.surface)
        infoBar.translatesAutoresizingMaskIntoConstraints = false
        rightPanel.addSubview(infoBar)
        favButton.target = self; favButton.action = #selector(toggleFavorite)
        let epgStack = NSStackView(views: [channelTitle, epgNow, epgNext])
        epgStack.orientation = .vertical; epgStack.spacing = 3; epgStack.alignment = .leading
        epgStack.translatesAutoresizingMaskIntoConstraints = false
        infoBar.addSubview(epgStack)
        infoBar.addSubview(favButton)

        NSLayoutConstraint.activate([
            leftPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            leftPanel.topAnchor.constraint(equalTo: view.topAnchor),
            leftPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            leftPanel.widthAnchor.constraint(equalToConstant: 330),

            categoryPopup.topAnchor.constraint(equalTo: leftPanel.topAnchor, constant: 16),
            categoryPopup.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor, constant: 14),
            categoryPopup.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor, constant: -14),
            searchField.topAnchor.constraint(equalTo: categoryPopup.bottomAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor, constant: -14),
            searchField.heightAnchor.constraint(equalToConstant: 30),
            tableScroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            tableScroll.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor, constant: 6),
            tableScroll.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor, constant: -6),
            tableScroll.bottomAnchor.constraint(equalTo: leftPanel.bottomAnchor, constant: -6),

            rightPanel.leadingAnchor.constraint(equalTo: leftPanel.trailingAnchor),
            rightPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rightPanel.topAnchor.constraint(equalTo: view.topAnchor),
            rightPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            playerContainer.topAnchor.constraint(equalTo: rightPanel.topAnchor),
            playerContainer.leadingAnchor.constraint(equalTo: rightPanel.leadingAnchor),
            playerContainer.trailingAnchor.constraint(equalTo: rightPanel.trailingAnchor),

            infoBar.topAnchor.constraint(equalTo: playerContainer.bottomAnchor),
            infoBar.leadingAnchor.constraint(equalTo: rightPanel.leadingAnchor),
            infoBar.trailingAnchor.constraint(equalTo: rightPanel.trailingAnchor),
            infoBar.bottomAnchor.constraint(equalTo: rightPanel.bottomAnchor),
            infoBar.heightAnchor.constraint(equalToConstant: 92),

            epgStack.leadingAnchor.constraint(equalTo: infoBar.leadingAnchor, constant: 20),
            epgStack.centerYAnchor.constraint(equalTo: infoBar.centerYAnchor),
            epgStack.trailingAnchor.constraint(lessThanOrEqualTo: favButton.leadingAnchor, constant: -16),
            favButton.trailingAnchor.constraint(equalTo: infoBar.trailingAnchor, constant: -20),
            favButton.centerYAnchor.constraint(equalTo: infoBar.centerYAnchor),
            favButton.widthAnchor.constraint(equalToConstant: 26)
        ])

        loading.translatesAutoresizingMaskIntoConstraints = false
        leftPanel.addSubview(loading)
        loading.pinEdges(to: tableScroll)
        loading.stop()
    }

    // MARK: Data

    private func loadCategories() {
        loading.start()
        Task { @MainActor in
            categories = (try? await coordinator.session.liveCategories()) ?? []
            categoryPopup.removeAllItems()
            categoryPopup.addItems(withTitles: ["All Channels", "★ Favorites"] + categories.map { $0.name })
            loadChannels()
        }
    }

    private func loadChannels() {
        loading.start()
        Task { @MainActor in
            if showingFavorites {
                let all = (try? await coordinator.session.loadAllLive()) ?? coordinator.session.allLive
                let favIDs = Set(coordinator.session.userData.favorites(of: .live).compactMap { $0.streamID })
                channels = all.filter { favIDs.contains($0.streamID) }
            } else if let catID = selectedCategoryID {
                channels = (try? await coordinator.session.client.liveStreams(categoryID: catID)) ?? []
            } else {
                channels = (try? await coordinator.session.loadAllLive()) ?? []
            }
            loading.stop()
            applyFilter()
        }
    }

    private func applyFilter() {
        filtered = filterText.isEmpty ? channels : channels.filter { $0.name.lowercased().contains(filterText) }
        tableView.reloadData()
    }

    func refresh() {
        if selectedCategoryID == nil && !showingFavorites {
            Task { @MainActor in _ = try? await coordinator.session.loadAllLive(forceRefresh: true); loadChannels() }
        } else {
            loadChannels()
        }
    }

    // MARK: Playback

    private func play(_ channel: LiveStream) {
        currentChannel = channel
        guard let item = coordinator.session.makeLiveItem(channel) else { return }
        placeholder.isHidden = true

        if let vc = playerVC {
            vc.replace(with: item)
        } else {
            let vc = PlayerViewController(session: coordinator.session, item: item, embedded: true)
            addChild(vc)
            vc.view.translatesAutoresizingMaskIntoConstraints = false
            playerContainer.addSubview(vc.view)
            vc.view.pinEdges(to: playerContainer)
            playerVC = vc
        }
        channelTitle.stringValue = channel.name
        updateFavIcon()
        loadEPG(for: channel)
    }

    private func loadEPG(for channel: LiveStream) {
        epgNow.stringValue = ""
        epgNext.stringValue = ""
        Task { @MainActor in
            let listings = (try? await coordinator.session.client.shortEPG(streamID: channel.streamID, limit: 2)) ?? []
            guard currentChannel?.streamID == channel.streamID else { return }
            let df = DateFormatter(); df.dateFormat = "HH:mm"
            if let now = listings.first {
                let time = now.start.map { df.string(from: $0) } ?? ""
                epgNow.stringValue = "Now: \(time.isEmpty ? "" : time + "  ")\(now.title)"
            } else {
                epgNow.stringValue = "No programme guide available"
            }
            if listings.count > 1 {
                let next = listings[1]
                let time = next.start.map { df.string(from: $0) } ?? ""
                epgNext.stringValue = "Next: \(time.isEmpty ? "" : time + "  ")\(next.title)"
            }
        }
    }

    // MARK: Actions

    @objc private func categoryChanged() {
        let idx = categoryPopup.indexOfSelectedItem
        showingFavorites = (idx == 1)
        selectedCategoryID = idx <= 1 ? nil : categories[idx - 2].id
        loadChannels()
    }
    @objc private func filterChanged() {
        filterText = searchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        applyFilter()
    }
    @objc private func toggleFavorite() {
        guard let channel = currentChannel else { return }
        _ = coordinator.session.userData.toggleFavorite(.live(channel))
        updateFavIcon()
    }
    private func updateFavIcon() {
        guard let channel = currentChannel else { return }
        let fav = coordinator.session.userData.isFavorite(.live(channel))
        favButton.setSymbol(fav ? "star.fill" : "star", pointSize: 16)
        favButton.contentTintColor = fav ? Theme.accent : Theme.textSecondary
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("ChannelCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? ChannelCellView) ?? ChannelCellView(id: id)
        cell.configure(filtered[row], number: filtered[row].num)
        return cell
    }

    func tableView(_ tableView: NSTableView, selectionShouldChange: NSTableView) -> Bool? { nil }
    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < filtered.count else { return }
        play(filtered[row])
    }
}

/// Channel row: logo, name, and channel number.
final class ChannelCellView: NSTableCellView {
    private let logo = AsyncImageView()
    private let nameLabel = makeLabel(font: Theme.Font.medium(13.5), color: Theme.textPrimary, lines: 1)
    private let numLabel = makeLabel(font: Theme.Font.regular(11), color: Theme.textTertiary)

    init(id: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        identifier = id
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.layer?.cornerRadius = 6
        addSubview(logo)
        let text = NSStackView(views: [nameLabel, numLabel])
        text.orientation = .vertical; text.spacing = 1; text.alignment = .leading
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        NSLayoutConstraint.activate([
            logo.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            logo.centerYAnchor.constraint(equalTo: centerYAnchor),
            logo.widthAnchor.constraint(equalToConstant: 42),
            logo.heightAnchor.constraint(equalToConstant: 42),
            text.leadingAnchor.constraint(equalTo: logo.trailingAnchor, constant: 10),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ channel: LiveStream, number: Int?) {
        nameLabel.stringValue = channel.name
        numLabel.stringValue = number.map { "CH \($0)" } ?? ""
        logo.load(channel.icon, placeholder: "tv")
    }
}
