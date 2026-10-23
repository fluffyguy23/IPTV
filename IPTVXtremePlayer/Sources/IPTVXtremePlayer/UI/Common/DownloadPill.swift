import AppKit

/// "Download This Video Offline" control. Reflects the live state of the
/// current title's download (queued / NN% / available offline / failed → retry)
/// and drives DownloadManager. Used on the player and on the movie detail page.
final class DownloadPill: NSView {
    /// The title this pill controls. Set to nil to hide (e.g. live channels).
    var item: PlaybackItem? { didSet { refresh() } }
    var profileID: UUID?

    private let icon = NSImageView()
    private let label = makeLabel(font: Theme.Font.semibold(12.5), color: .white)
    private var observer: NSObjectProtocol?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(clicked)))
        observer = NotificationCenter.default.addObserver(forName: .downloadsChanged, object: nil, queue: .main) { [weak self] note in
            guard let self = self, let id = note.userInfo?["id"] as? String, id == self.item?.ref.key else { return }
            self.refresh()
        }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { observer.map(NotificationCenter.default.removeObserver) }

    private func style(symbol: String, text: String, tint: NSColor, fill: NSColor, tip: String? = nil) {
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        icon.contentTintColor = tint
        label.stringValue = text
        label.textColor = tint == Theme.accent ? .white : tint
        layer?.backgroundColor = fill.cgColor
        layer?.borderColor = tint.withAlphaComponent(0.6).cgColor
        toolTip = tip
        setAccessibilityLabel(text)
    }

    func refresh() {
        guard let item = item, !item.isLive else { isHidden = true; return }
        isHidden = false
        let r = DownloadManager.shared.record(for: item.ref)
        switch r?.status {
        case .completed?:
            style(symbol: "checkmark.circle.fill", text: "Available Offline", tint: Theme.positive,
                  fill: Theme.positive.withAlphaComponent(0.12), tip: "Saved on this Mac — plays without internet.")
        case .downloading?:
            let pct = Int(((r?.progress ?? 0) * 100).rounded())
            let text = (r?.bytesExpected ?? 0) > 0 ? "Downloading \(pct)%" : "Downloading…"
            style(symbol: "arrow.down.circle", text: text, tint: Theme.accent, fill: Theme.accentSoft,
                  tip: "Click to cancel the download.")
        case .queued?:
            style(symbol: "clock", text: "Queued for Download", tint: Theme.accent, fill: Theme.accentSoft,
                  tip: "Click to cancel.")
        case .failed?:
            style(symbol: "exclamationmark.triangle.fill", text: "Download Failed — Retry", tint: Theme.negative,
                  fill: Theme.negative.withAlphaComponent(0.12), tip: r?.errorMessage)
        case nil:
            style(symbol: "arrow.down.circle", text: "Download This Video Offline", tint: Theme.accent,
                  fill: NSColor.black.withAlphaComponent(0.35), tip: "Save this title on this Mac to watch offline.")
        }
    }

    @objc private func clicked() {
        guard let item = item else { return }
        let mgr = DownloadManager.shared
        switch mgr.record(for: item.ref)?.status {
        case .completed?:
            return
        case .downloading?, .queued?:
            let alert = NSAlert()
            alert.messageText = "Cancel this download?"
            alert.informativeText = "You can retry it later from Downloads."
            alert.addButton(withTitle: "Cancel Download")
            alert.addButton(withTitle: "Keep Downloading")
            if alert.runModal() == .alertFirstButtonReturn { mgr.cancel(id: item.ref.key) }
        case .failed?, nil:
            let result: DownloadManager.EnqueueResult
            if item.isLocal {
                result = mgr.retry(id: item.ref.key, session: AppState.shared.session)
            } else {
                result = mgr.enqueue(item, profileID: profileID ?? AppState.shared.session?.profile.id ?? UUID())
            }
            if case .rejected(let why) = result {
                let alert = NSAlert()
                alert.messageText = "Can't download this title"
                alert.informativeText = why
                alert.runModal()
            }
        }
        refresh()
    }
}
