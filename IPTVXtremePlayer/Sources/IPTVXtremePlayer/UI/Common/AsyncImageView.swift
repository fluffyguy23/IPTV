import AppKit

/// Image view that loads from a URL via the shared cache, showing an SF-symbol
/// placeholder until the image arrives. Cancels stale loads on reuse.
final class AsyncImageView: NSImageView {
    private var currentURL: String?
    private var loadTask: Task<Void, Never>?
    private var placeholderSymbol = "photo"

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        imageScaling = .scaleProportionallyUpOrDown
        layer?.backgroundColor = Theme.surfaceRaised.cgColor
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func load(_ urlString: String?, placeholder: String = "photo") {
        loadTask?.cancel()
        placeholderSymbol = placeholder
        currentURL = urlString
        showPlaceholder()
        guard let urlString = urlString, !urlString.isEmpty else { return }
        loadTask = Task { [weak self] in
            let img = await ImageCache.shared.image(for: urlString)
            await MainActor.run {
                guard let self = self, self.currentURL == urlString, let img = img else { return }
                self.imageScaling = .scaleProportionallyUpOrDown
                self.image = img
            }
        }
    }

    private func showPlaceholder() {
        let config = NSImage.SymbolConfiguration(pointSize: 30, weight: .regular)
        image = NSImage(systemSymbolName: placeholderSymbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        contentTintColor = Theme.textTertiary
        imageScaling = .scaleNone
    }
}
