import AppKit

/// Something that can reload itself when the user hits Refresh.
protocol Refreshable: AnyObject { func refresh() }

/// Thin window wrapper. All shell/navigation logic lives in RootViewController
/// so child view controllers get proper appearance lifecycle callbacks.
final class MainWindowController: NSWindowController {
    init() {
        // Size to the display's usable area so the window always fits the screen
        // (important on a 13" MacBook). Min size kept small enough for Ventura laptops.
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let minW: CGFloat = 860, minH: CGFloat = 560
        let w = min(1180, max(minW, visible.width - 40))
        let h = min(760, max(minH, visible.height - 40))

        // No .fullSizeContentView: content sits below the titlebar so the sidebar
        // never collides with the window traffic-light buttons.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "IPTVXtremePlayer"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = Theme.background
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: minW, height: minH)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.center()
        window.contentViewController = RootViewController()
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Owns the sidebar / top-bar shell and the content navigation stack, and acts
/// as the app coordinator. Swaps between the connection screen and the library.
final class RootViewController: NSViewController, AppCoordinator {

    private let sidebar = SidebarView()
    private let topBar = TopBarView()
    private let contentArea = NSView()

    private var navStack: [NSViewController] = []
    private var currentChild: NSViewController?
    private var currentSection: Section = .home
    private var shellBuilt = false
    private var autoConnectTried = false

    var session: Session { AppState.shared.session! }

    override func loadView() {
        view = NSView()
        view.fill(Theme.background)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(sessionChanged),
                                               name: .sessionChanged, object: nil)
        renderForSessionState()
    }

    @objc private func sessionChanged() { renderForSessionState() }

    private func renderForSessionState() {
        view.subviews.forEach { $0.removeFromSuperview() }
        children.forEach { $0.removeFromParent() }
        currentChild = nil
        navStack.removeAll()
        shellBuilt = false

        if AppState.shared.isConnected {
            buildLibraryShell()
        } else if !autoConnectTried, let last = ProfileStore.shared.lastUsedProfile {
            autoConnectTried = true
            autoConnect(to: last)
        } else {
            buildConnectionScreen()
        }
    }

    // MARK: Auto-connect (seamless relaunch / post-update)

    private func autoConnect(to profile: Profile) {
        let loading = LoadingView(message: "Connecting to \(profile.name)…")
        loading.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loading)
        loading.pinEdges(to: view)
        loading.start()
        let id = profile.id
        Task { @MainActor in
            // Read the credential once, off the main thread (avoids a possible
            // synchronous Keychain prompt blocking launch on the migration path).
            let password = await Task.detached(priority: .userInitiated) {
                CredentialStore.password(for: id)
            }.value
            guard let password = password else {
                loading.removeFromSuperview()
                buildConnectionScreen()
                return
            }
            do {
                try await AppState.shared.connect(profile: profile, password: password)
                // .sessionChanged fires → renderForSessionState builds the shell.
            } catch {
                loading.removeFromSuperview()
                buildConnectionScreen()
            }
        }
    }

    // MARK: Connection screen

    private func buildConnectionScreen() {
        let vc = ConnectionViewController()
        addChild(vc)
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(vc.view)
        vc.view.pinEdges(to: view)
        currentChild = vc
    }

    // MARK: Library shell

    private func buildLibraryShell() {
        shellBuilt = true
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        topBar.translatesAutoresizingMaskIntoConstraints = false
        contentArea.translatesAutoresizingMaskIntoConstraints = false
        contentArea.fill(Theme.background)

        view.addSubview(sidebar)
        view.addSubview(topBar)
        view.addSubview(contentArea)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: view.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: Theme.sidebarWidth),

            topBar.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.heightAnchor.constraint(equalToConstant: Theme.topBarHeight),

            contentArea.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            contentArea.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentArea.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            contentArea.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        sidebar.onSelect = { [weak self] section in self?.selectSection(section) }
        sidebar.onDisconnect = { [weak self] in self?.confirmDisconnect() }
        topBar.coordinator = self
        topBar.configure(profileName: session.profile.name, status: session.auth.userInfo?.status)
        topBar.onBack = { [weak self] in self?.pop() }

        selectSection(.home)
    }

    private func confirmDisconnect() {
        let alert = NSAlert()
        alert.messageText = "Disconnect from \(session.profile.name)?"
        alert.informativeText = "You can reconnect any time from the connection screen."
        alert.addButton(withTitle: "Disconnect")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            AppState.shared.disconnect()
        }
    }

    // MARK: AppCoordinator

    func selectSection(_ section: Section) {
        currentSection = section
        sidebar.setSelected(section)
        navStack = [rootViewController(for: section)]
        showTop(animated: false)
    }

    func push(_ viewController: NSViewController) {
        navStack.append(viewController)
        showTop(animated: true)
    }

    func pop() {
        guard navStack.count > 1 else { return }
        navStack.removeLast()
        showTop(animated: true)
    }

    func performSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sidebar.setSelected(nil)
        navStack = [SearchViewController(coordinator: self, query: trimmed)]
        showTop(animated: false)
    }

    func refreshCurrentProfile() {
        (navStack.last as? Refreshable)?.refresh()
    }

    func openMovie(_ movie: VODStream) {
        push(VODDetailViewController(coordinator: self, movie: movie))
    }

    func openSeries(_ series: SeriesStream) {
        push(SeriesDetailViewController(coordinator: self, series: series))
    }

    func playInWindow(_ item: PlaybackItem, navigator: EpisodeNavigator?) {
        PlayerWindowController.present(session: session, item: item, navigator: navigator)
    }

    func play(ref: MediaRef) {
        guard let item = session.makeItem(from: ref) else {
            presentError("This item can no longer be played.")
            return
        }
        playInWindow(item, navigator: nil)
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Playback error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: Navigation plumbing

    private func rootViewController(for section: Section) -> NSViewController {
        switch section {
        case .home: return HomeViewController(coordinator: self)
        case .liveTV: return LiveTVViewController(coordinator: self)
        case .movies: return MediaGridViewController(coordinator: self, kind: .movies)
        case .series: return MediaGridViewController(coordinator: self, kind: .series)
        case .favorites: return FavoritesViewController(coordinator: self)
        case .recent: return RecentViewController(coordinator: self)
        case .downloads: return DownloadsViewController()
        case .settings: return SettingsViewController(coordinator: self)
        }
    }

    private func showTop(animated: Bool) {
        guard shellBuilt, let top = navStack.last else { return }
        currentChild?.view.removeFromSuperview()
        currentChild?.removeFromParent()

        addChild(top)
        top.view.translatesAutoresizingMaskIntoConstraints = false
        contentArea.addSubview(top.view)
        top.view.pinEdges(to: contentArea)
        currentChild = top

        topBar.setBackVisible(navStack.count > 1)
        topBar.setTitle(navStack.count > 1 ? "" : currentSection.title)

        if animated {
            top.view.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                top.view.animator().alphaValue = 1
            }
        }
    }
}
