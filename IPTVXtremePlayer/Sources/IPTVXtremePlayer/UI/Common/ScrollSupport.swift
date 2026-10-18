import AppKit

/// Base controller offering a vertical scroll view with a top-anchored content
/// stack, plus swappable loading / empty overlays.
class VScrollController: NSViewController {
    let coordinator: AppCoordinator
    let scroll = NSScrollView()
    let contentStack = NSStackView()
    private let overlayContainer = NSView()

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView()
        view.fill(Theme.background)

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 8, left: 0, bottom: 24, right: 0)
        view.addSubview(scroll)
        scroll.pinEdges(to: view)

        let flipped = FlippedView()
        flipped.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = flipped

        contentStack.orientation = .vertical
        contentStack.spacing = 26
        contentStack.alignment = .leading
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        flipped.addSubview(contentStack)

        NSLayoutConstraint.activate([
            flipped.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            contentStack.topAnchor.constraint(equalTo: flipped.topAnchor, constant: 24),
            contentStack.leadingAnchor.constraint(equalTo: flipped.leadingAnchor, constant: 28),
            contentStack.trailingAnchor.constraint(equalTo: flipped.trailingAnchor, constant: -28),
            contentStack.bottomAnchor.constraint(equalTo: flipped.bottomAnchor, constant: -24)
        ])

        overlayContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayContainer)
        overlayContainer.pinEdges(to: view)
        overlayContainer.isHidden = true
    }

    func clearContent() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    /// Add a view to the content stack stretched to the full content width.
    func addFullWidth(_ v: NSView) {
        contentStack.addArrangedSubview(v)
        v.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    func showOverlay(_ overlayView: NSView?) {
        overlayContainer.subviews.forEach { $0.removeFromSuperview() }
        guard let overlayView = overlayView else { overlayContainer.isHidden = true; return }
        overlayContainer.isHidden = false
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayContainer.addSubview(overlayView)
        overlayView.pinEdges(to: overlayContainer)
    }

    func showLoading(_ message: String = "Loading…") { showOverlay(LoadingView(message: message)) }
    func showEmpty(symbol: String, title: String, message: String) {
        showOverlay(EmptyStateView(symbol: symbol, title: title, message: message))
    }
    func hideOverlay() { showOverlay(nil) }
}

/// Builds a titled horizontal rail of cards.
enum Rail {
    static func make(title: String, cards: [NSView]) -> NSView {
        let header = makeLabel(title, font: Theme.Font.semibold(18))

        let row = NSStackView(views: cards)
        row.orientation = .horizontal
        row.spacing = 16
        row.alignment = .top
        row.translatesAutoresizingMaskIntoConstraints = false

        let hScroll = NSScrollView()
        hScroll.drawsBackground = false
        hScroll.hasHorizontalScroller = false
        hScroll.hasVerticalScroller = false
        hScroll.translatesAutoresizingMaskIntoConstraints = false
        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(row)
        hScroll.documentView = doc
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: doc.topAnchor),
            row.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            doc.heightAnchor.constraint(equalTo: hScroll.heightAnchor)
        ])

        let stack = NSStackView(views: [header, hScroll])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        hScroll.heightAnchor.constraint(equalToConstant: Theme.posterHeight + 48).isActive = true
        hScroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }
}
