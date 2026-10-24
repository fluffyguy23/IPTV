import AppKit

/// Hosts the player in its own window for movies and series episodes.
final class PlayerWindowController: NSWindowController, NSWindowDelegate {
    private static var active: PlayerWindowController?

    private let playerVC: PlayerViewController
    /// Called once the window has closed (Live TV resumes its embedded player).
    var onClosed: (() -> Void)?

    @discardableResult
    static func present(session: Session, item: PlaybackItem,
                        navigator: EpisodeNavigator? = nil) -> PlayerWindowController {
        present(userData: session.userData, profileID: session.profile.id, item: item, navigator: navigator)
    }

    /// Present without a live session (offline downloads while disconnected).
    @discardableResult
    static func present(userData: UserData?, profileID: UUID?, item: PlaybackItem,
                        navigator: EpisodeNavigator? = nil) -> PlayerWindowController {
        active?.close()
        let wc = PlayerWindowController(userData: userData, profileID: profileID, item: item, navigator: navigator)
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        active = wc
        return wc
    }

    private init(userData: UserData?, profileID: UUID?, item: PlaybackItem, navigator: EpisodeNavigator?) {
        // Navigator is passed into init so it exists before contentViewController
        // forces the view (and the control bar) to load.
        playerVC = PlayerViewController(userData: userData, profileID: profileID, item: item,
                                        embedded: false, navigator: navigator)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 580),
            // .fullSizeContentView makes the video full-bleed under the transparent
            // titlebar; the player's own title inset clears the traffic lights.
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = item.title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        window.minSize = NSSize(width: 640, height: 400)
        window.contentViewController = playerVC
        super.init(window: window)
        window.delegate = self
        playerVC.onClose = { [weak self] in self?.close() }
    }
    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        let closed = onClosed
        onClosed = nil
        DispatchQueue.main.async { closed?() }   // after this window's player has stopped
        if PlayerWindowController.active === self { PlayerWindowController.active = nil }
    }
}
