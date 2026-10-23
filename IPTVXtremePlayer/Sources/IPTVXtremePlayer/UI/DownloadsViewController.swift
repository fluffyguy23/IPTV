import AppKit

/// Offline Downloads: every saved / in-progress / failed download with its
/// artwork, status and progress, plus Play, Cancel, Retry and Delete.
/// Needs no connected session, so it also works with the internet off
/// (opened from the connection screen).
final class DownloadsViewController: NSViewController {
    private let scroll = NSScrollView()
    private let stack = NSStackView()
    private var rows: [String: DownloadRow] = [:]
    private var observer: NSObjectProtocol?
    private let summary = makeLabel(font: Theme.Font.medium(12.5), color: Theme.textSecondary)

    override func loadView() {
        view = NSView()
        view.fill(Theme.background)

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.automaticallyAdjustsContentInsets = false
        view.addSubview(scroll)
        scroll.pinEdges(to: view)

        let flipped = FlippedView()
        flipped.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = flipped
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        flipped.addSubview(stack)
        NSLayoutConstraint.activate([
            flipped.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            stack.topAnchor.constraint(equalTo: flipped.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: flipped.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: flipped.trailingAnchor, constant: -28),
            stack.bottomAnchor.constraint(equalTo: flipped.bottomAnchor, constant: -24)
        ])

        observer = NotificationCenter.default.addObserver(forName: .downloadsChanged, object: nil, queue: .main) { [weak self] note in
            guard let self = self else { return }
            let id = note.userInfo?["id"] as? String
            let statusChanged = note.userInfo?["statusChanged"] as? Bool ?? true
            if !statusChanged, let id = id, let row = self.rows[id], let r = DownloadManager.shared.record(id: id) {
                row.update(r)          // progress tick: update in place
            } else {
                self.build()
            }
        }
        build()
    }

    deinit { observer.map(NotificationCenter.default.removeObserver) }

    private func add(_ v: NSView) {
        stack.addArrangedSubview(v)
        v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func build() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rows.removeAll()
        let mgr = DownloadManager.shared

        add(makeLabel("Offline Downloads", font: Theme.Font.bold(22)))
        let used = ByteCountFormatter.string(fromByteCount: mgr.bytesOnDisk, countStyle: .file)
        let free = ByteCountFormatter.string(fromByteCount: DownloadManager.freeDiskBytes(), countStyle: .file)
        summary.stringValue = "\(mgr.completedCount) available offline  ·  \(used) used  ·  \(free) free on this Mac"
        add(summary)
        let note = makeLabel("Downloads use one of your provider's connections — on a single-connection plan, streaming may fail while a download is running.",
                             font: Theme.Font.regular(11.5), color: Theme.textTertiary, lines: 2)
        add(note)
        stack.setCustomSpacing(18, after: note)

        if mgr.records.isEmpty {
            let empty = EmptyStateView(symbol: "arrow.down.circle", title: "No downloads yet",
                                       message: "Open a movie or episode and click “Download This Video Offline” to watch it later without internet.")
            empty.translatesAutoresizingMaskIntoConstraints = false
            empty.heightAnchor.constraint(equalToConstant: 320).isActive = true
            add(empty)
            return
        }
        for r in mgr.records {
            let row = DownloadRow(record: r)
            row.onPlay = { [weak self] in self?.play(r.id) }
            row.onCancel = { DownloadManager.shared.cancel(id: r.id) }
            row.onRetry = { [weak self] in self?.retry(r.id) }
            row.onDelete = { [weak self] in self?.confirmDelete(r.id) }
            rows[r.id] = row
            add(row)
        }
    }

    // MARK: Actions

    private func play(_ id: String) {
        let mgr = DownloadManager.shared
        guard let r = mgr.record(id: id), let file = mgr.localFileURL(for: r.ref) else {
            alert("This download isn't available.", "It may still be downloading or the file was removed.")
            return
        }
        // Reuse the connected profile's history store when it's the same profile,
        // otherwise open that profile's store directly (works fully offline).
        let session = AppState.shared.session
        let userData = session?.profile.id == r.profileID ? session?.userData : UserData(profileID: r.profileID)
        let item = PlaybackItem(ref: r.ref, url: file, title: r.title, isLive: false,
                                resumeSecs: userData?.resumePosition(for: r.ref) ?? 0, networkCaching: 600)
        PlayerWindowController.present(userData: userData, profileID: r.profileID, item: item)
    }

    private func retry(_ id: String) {
        if case .rejected(let why) = DownloadManager.shared.retry(id: id, session: AppState.shared.session) {
            alert("Can't retry this download", why)
        }
    }

    private func confirmDelete(_ id: String) {
        guard let r = DownloadManager.shared.record(id: id) else { return }
        let a = NSAlert()
        a.messageText = "Delete “\(r.title)”?"
        a.informativeText = r.status == .completed
            ? "The downloaded file will be removed from this Mac to free up space."
            : "The download will be stopped and removed."
        a.addButton(withTitle: "Delete")
        a.addButton(withTitle: "Cancel")
        a.alertStyle = .warning
        if a.runModal() == .alertFirstButtonReturn { DownloadManager.shared.delete(id: id) }
    }

    private func alert(_ title: String, _ message: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = message; a.runModal()
    }
}

/// One download: thumbnail, title, status line, progress bar and actions.
final class DownloadRow: NSView {
    var onPlay: (() -> Void)?
    var onCancel: (() -> Void)?
    var onRetry: (() -> Void)?
    var onDelete: (() -> Void)?

    private let poster = AsyncImageView()
    private let title = makeLabel(font: Theme.Font.semibold(14), color: Theme.textPrimary)
    private let status = makeLabel(font: Theme.Font.regular(12), color: Theme.textSecondary, lines: 2)
    private let bar = NSProgressIndicator()
    private let actions = NSStackView()

    init(record: DownloadRecord) {
        super.init(frame: .zero)
        fill(Theme.surface, corner: 10)
        translatesAutoresizingMaskIntoConstraints = false

        poster.translatesAutoresizingMaskIntoConstraints = false
        poster.layer?.cornerRadius = 6
        poster.load(record.ref.poster, placeholder: record.ref.kind == .movie ? "film" : "rectangle.stack")

        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0; bar.maxValue = 1
        bar.controlSize = .small
        bar.translatesAutoresizingMaskIntoConstraints = false

        let text = NSStackView(views: [title, status, bar])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 5
        text.translatesAutoresizingMaskIntoConstraints = false

        actions.spacing = 10
        actions.alignment = .centerY
        actions.translatesAutoresizingMaskIntoConstraints = false

        addSubview(poster)
        addSubview(text)
        addSubview(actions)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 104),
            poster.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            poster.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            poster.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),
            poster.widthAnchor.constraint(equalToConstant: 54),
            poster.heightAnchor.constraint(equalToConstant: 80),
            text.leadingAnchor.constraint(equalTo: poster.trailingAnchor, constant: 14),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: actions.leadingAnchor, constant: -16),
            bar.widthAnchor.constraint(equalToConstant: 260),
            actions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            actions.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        update(record)
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(_ r: DownloadRecord) {
        title.stringValue = r.title
        let fmt = { (b: Int64) in ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }
        switch r.status {
        case .completed:
            status.stringValue = "✓ Downloaded · \(fmt(r.bytesExpected)) · plays without internet"
            status.textColor = Theme.positive
            bar.isHidden = true
        case .downloading:
            let pct = Int((r.progress * 100).rounded())
            status.stringValue = r.bytesExpected > 0
                ? "Downloading · \(pct)% · \(fmt(r.bytesWritten)) of \(fmt(r.bytesExpected))"
                : "Downloading · \(fmt(r.bytesWritten))"
            status.textColor = Theme.accent
            bar.isHidden = false
            bar.isIndeterminate = r.bytesExpected <= 0
            if r.bytesExpected > 0 { bar.doubleValue = r.progress } else { bar.startAnimation(nil) }
        case .queued:
            status.stringValue = "Queued — starts when the current download finishes"
            status.textColor = Theme.textSecondary
            bar.isHidden = false
            bar.isIndeterminate = false
            bar.doubleValue = 0
        case .failed:
            status.stringValue = "Download failed — \(r.errorMessage ?? "unknown error")"
            status.textColor = Theme.negative
            bar.isHidden = true
        }
        setActions(for: r.status)
    }

    private var shownStatus: DownloadRecord.Status?

    private func setActions(for s: DownloadRecord.Status) {
        guard s != shownStatus else { return }
        shownStatus = s
        actions.arrangedSubviews.forEach { $0.removeFromSuperview() }
        func pill(_ t: String, filled: Bool, _ action: @escaping () -> Void) -> PillButton {
            let b = PillButton(title: t, filled: filled); b.onClick = action; return b
        }
        switch s {
        case .completed: actions.addArrangedSubview(pill("Play", filled: true) { [weak self] in self?.onPlay?() })
        case .downloading, .queued: actions.addArrangedSubview(pill("Cancel", filled: false) { [weak self] in self?.onCancel?() })
        case .failed: actions.addArrangedSubview(pill("Retry", filled: true) { [weak self] in self?.onRetry?() })
        }
        let del = IconButton(symbol: "trash", pointSize: 14, tint: Theme.textSecondary, hover: Theme.negative,
                             accessibility: "Delete download")
        del.target = self
        del.action = #selector(deleteTapped)
        del.toolTip = "Delete download"
        del.widthAnchor.constraint(equalToConstant: 26).isActive = true
        actions.addArrangedSubview(del)
    }

    @objc private func deleteTapped() { onDelete?() }
}

/// Stand-alone window for Offline Downloads, used from the connection screen
/// (no session needed — e.g. when there is no internet).
final class DownloadsWindowController: NSWindowController {
    private static var shared: DownloadsWindowController?

    static func show() {
        if shared == nil { shared = DownloadsWindowController() }
        shared?.showWindow(nil)
        shared?.window?.makeKeyAndOrderFront(nil)
    }

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Offline Downloads"
        window.backgroundColor = Theme.background
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 620, height: 380)
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = DownloadsViewController()
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError() }
}
