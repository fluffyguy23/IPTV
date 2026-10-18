import AppKit

/// Hosts the player in its own window for movies and series episodes.
final class PlayerWindowController: NSWindowController, NSWindowDelegate {
    private static var active: PlayerWindowController?

    private let playerVC: PlayerViewController

    @discardableResult
    static func present(session: Session, item: PlaybackItem,
                        navigator: EpisodeNavigator? = nil) -> PlayerWindowController {
        active?.close()
        let wc = PlayerWindowController(session: session, item: item, navigator: navigator)
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        active = wc
        return wc
    }

    private init(session: Session, item: PlaybackItem, navigator: EpisodeNavigator?) {
        // Navigator is passed into init so it exists before contentViewController
        // forces the view (and the control bar) to load.
        playerVC = PlayerViewController(session: session, item: item, embedded: false, navigator: navigator)
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
        if PlayerWindowController.active === self { PlayerWindowController.active = nil }
    }
}
