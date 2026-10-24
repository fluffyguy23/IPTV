import AppKit

/// Full playback surface with an auto-hiding control bar. Reused both embedded
/// (Live TV) and inside a dedicated window (movies / series).
final class PlayerViewController: NSViewController {
    /// Where resume points / history go. Nil only if no profile is known.
    private let userData: UserData?
    private let profileID: UUID?
    private var item: PlaybackItem
    private let embedded: Bool
    private let player = VLCPlayer()

    /// Called when the user dismisses the player (close button / Esc when windowed).
    var onClose: (() -> Void)?
    /// Present only for series episodes — drives Prev/Next and auto-advance.
    var navigator: EpisodeNavigator?

    private let videoView = VideoContainerView()
    private let topBar = GradientView()
    private let bottomBar = GradientView()
    private let titleLabel = makeLabel(font: Theme.Font.semibold(15))
    private let spinner = NSProgressIndicator()
    private let errorLabel = makeLabel(font: Theme.Font.medium(14), color: Theme.textSecondary, align: .center, lines: 3)

    private lazy var playPause = IconButton(symbol: "pause.fill", pointSize: 20)
    private lazy var back10 = IconButton(symbol: "gobackward.10", pointSize: 17)
    private lazy var forward10 = IconButton(symbol: "goforward.10", pointSize: 17)
    private lazy var prevEpisode = IconButton(symbol: "backward.end.fill", pointSize: 15)
    private lazy var nextEpisode = IconButton(symbol: "forward.end.fill", pointSize: 15)
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let elapsed = makeLabel("0:00", font: Theme.Font.medium(12), color: Theme.textSecondary)
    private let duration = makeLabel("0:00", font: Theme.Font.medium(12), color: Theme.textSecondary)
    private lazy var muteButton = IconButton(symbol: "speaker.wave.2.fill", pointSize: 14)
    private let volume = NSSlider(value: 100, minValue: 0, maxValue: 125, target: nil, action: nil)
    private lazy var settingsButton = IconButton(symbol: "gearshape.fill", pointSize: 15)
    private lazy var fullscreenButton = IconButton(symbol: "arrow.up.left.and.arrow.down.right", pointSize: 14)
    private lazy var closeButton = IconButton(symbol: "xmark", pointSize: 14)
    private let downloadPill = DownloadPill()
    private let liveTag = makeLabel("● LIVE", font: Theme.Font.bold(11), color: Theme.negative)

    private var userScrubbing = false
    private var didApplyResume = false
    private var lastSaved: TimeInterval = 0

    // MARK: Recovery state
    // libVLC reports `.ended` (not `.error`) when an HTTP stream stops early — e.g.
    // the provider drops the connection and refuses the reconnect (expired VOD
    // token / connection limit). Treating that as "movie finished" used to close
    // the player mid-film. We now compare the last good position with the length
    // and reconnect (resuming in place) unless the title genuinely finished.
    private static let maxRecoveryAttempts = 5
    private static let recoveryDelays: [TimeInterval] = [1, 2, 4, 8, 15]
    /// Last position seen while actually playing (libVLC can reset time at EOF).
    private var lastGoodTimeMs: Int64 = 0
    private var knownLengthMs: Int64 = 0
    private var recoveryAttempts = 0
    private var recovering = false
    private var recoveryWork: DispatchWorkItem?
    /// Position to restore after a reconnect (overrides item.resumeSecs once).
    private var pendingResumeMs: Int64?
    /// Where playback stood when the current recovery began (for the stability reset).
    private var recoveredAtMs: Int64 = 0
    private var endHandled = false
    private var lastLoggedState: VLCPlayer.State = .nothing
    /// Stopped because the view left the screen (window minimized, section switch).
    private var stoppedByDisappear = false
    /// Embedded (Live TV) player: ask the host to open a dedicated full-screen window.
    var onFullscreenRequest: (() -> Void)?
    private let retryButton = PillButton(title: "Retry")
    private var hideWorkItem: DispatchWorkItem?
    private var aspectRatio: String?

    convenience init(session: Session, item: PlaybackItem, embedded: Bool, navigator: EpisodeNavigator? = nil) {
        self.init(userData: session.userData, profileID: session.profile.id, item: item,
                  embedded: embedded, navigator: navigator)
    }

    /// Designated init — needs no live session, so offline downloads can play
    /// while disconnected.
    init(userData: UserData?, profileID: UUID?, item: PlaybackItem, embedded: Bool, navigator: EpisodeNavigator? = nil) {
        self.userData = userData
        self.profileID = profileID
        self.item = item
        self.embedded = embedded
        self.navigator = navigator   // must be set before loadView builds the control bar
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView()
        view.fill(.black)
        buildUI()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(videoView)
        if player.state == .nothing {
            start()
        } else if stoppedByDisappear {
            // Came back (e.g. window un-minimized): continue where we were.
            stoppedByDisappear = false
            if !item.isLive && lastGoodTimeMs > 0 { pendingResumeMs = lastGoodTimeMs }
            start()
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        saveProgress(force: true)
        cancelRecovery()
        stoppedByDisappear = true
        player.stop()
    }

    /// Stop without tearing down (e.g. handing the stream to the full-screen window,
    /// so a single-connection plan isn't used twice).
    func suspendPlayback() {
        cancelRecovery()
        saveProgress(force: true)
        player.stop()
    }

    /// Restart the current item after suspendPlayback().
    func resumePlayback() {
        guard view.window != nil else { stoppedByDisappear = true; return }
        start()
    }

    // MARK: Build

    private func buildUI() {
        videoView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(videoView)
        videoView.pinEdges(to: view)
        videoView.onMouseMoved = { [weak self] in self?.revealControls() }
        videoView.onKeyDown = { [weak self] e in self?.handleKey(e) ?? false }

        // Spinner — isDisplayedWhenStopped=false is the fix for the "spinner
        // stuck over the video" bug: stopping the animation now hides it too.
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        spinner.appearance = NSAppearance(named: .darkAqua)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        // Error
        errorLabel.isHidden = true
        view.addSubview(errorLabel)
        NSLayoutConstraint.activate([
            errorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 420)
        ])
        retryButton.isHidden = true
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.onClick = { [weak self] in self?.retryAfterFailure() }
        view.addSubview(retryButton)
        NSLayoutConstraint.activate([
            retryButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            retryButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 16)
        ])

        buildTopBar()
        buildBottomBar()
    }

    private func buildTopBar() {
        topBar.colors = [NSColor.black.withAlphaComponent(0.75), .clear]
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)
        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 72)
        ])
        titleLabel.stringValue = item.title
        topBar.addSubview(titleLabel)
        closeButton.target = self
        closeButton.action = #selector(close)
        closeButton.isHidden = embedded
        topBar.addSubview(closeButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        // "Download This Video Offline" — only for movies/episodes (the embedded
        // Live TV player never shows it, so the title keeps its full width there).
        if !item.isLive {
            downloadPill.profileID = profileID
            downloadPill.item = item
            topBar.addSubview(downloadPill)
            NSLayoutConstraint.activate([
                downloadPill.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -14),
                downloadPill.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: downloadPill.leadingAnchor, constant: -12)
            ])
        }
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: embedded ? 20 : 82),
            titleLabel.topAnchor.constraint(equalTo: topBar.topAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -12),
            closeButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -18),
            closeButton.topAnchor.constraint(equalTo: topBar.topAnchor, constant: 14),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    private func buildBottomBar() {
        bottomBar.colors = [.clear, NSColor.black.withAlphaComponent(0.85)]
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)
        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 92)
        ])

        playPause.target = self; playPause.action = #selector(togglePlay)
        back10.target = self; back10.action = #selector(seekBack10)
        forward10.target = self; forward10.action = #selector(seekForward10)
        prevEpisode.target = self; prevEpisode.action = #selector(goPrevEpisode)
        nextEpisode.target = self; nextEpisode.action = #selector(goNextEpisode)
        muteButton.target = self; muteButton.action = #selector(toggleMute)
        settingsButton.target = self; settingsButton.action = #selector(showSettings)
        fullscreenButton.target = self; fullscreenButton.action = #selector(toggleFullscreen)

        slider.target = self; slider.action = #selector(scrub)
        slider.isContinuous = true
        styleSlider(slider)
        slider.isHidden = item.isLive

        volume.target = self; volume.action = #selector(volumeChanged)
        volume.isContinuous = true
        styleSlider(volume)

        liveTag.isHidden = !item.isLive
        duration.isHidden = item.isLive

        // Left transport cluster. Episode buttons only when a navigator exists;
        // 10s buttons only make sense for seekable (non-live) media.
        var transport: [NSView] = []
        if navigator != nil { transport.append(prevEpisode) }
        if !item.isLive { transport.append(back10) }
        transport.append(playPause)
        if !item.isLive { transport.append(forward10) }
        if navigator != nil { transport.append(nextEpisode) }
        transport.append(elapsed)
        let leftStack = NSStackView(views: transport)
        leftStack.spacing = 12
        leftStack.alignment = .centerY

        let rightTime = item.isLive ? liveTag : duration
        let rightStack = NSStackView(views: [rightTime, muteButton, volume, settingsButton, fullscreenButton])
        rightStack.spacing = 12
        rightStack.alignment = .centerY

        let row = NSStackView(views: [leftStack, slider, rightStack])
        row.spacing = 14
        row.alignment = .centerY
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 20),
            row.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -20),
            row.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -22),
            slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            volume.widthAnchor.constraint(equalToConstant: 90),
            playPause.widthAnchor.constraint(equalToConstant: 26),
            playPause.heightAnchor.constraint(equalToConstant: 26)
        ])
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        updateEpisodeButtons()
    }

    private func styleSlider(_ s: NSSlider) {
        s.translatesAutoresizingMaskIntoConstraints = false
        if let cell = s.cell as? NSSliderCell {
            cell.controlSize = .small
        }
    }

    // MARK: Playback

    private func start() {
        didApplyResume = false
        endHandled = false
        stoppedByDisappear = false
        knownLengthMs = 0
        if pendingResumeMs == nil { lastGoodTimeMs = 0 }
        setBuffering(true)
        errorLabel.isHidden = true
        retryButton.isHidden = true
        player.attach(to: videoView)
        player.onTick = { [weak self] t, l, state in self?.tick(timeMs: t, lengthMs: l, state: state) }
        player.load(url: item.url, options: item.mediaOptions)
        player.volume = 100
        player.play()
        userData?.recordPlay(item.ref)
        revealControls()
    }

    /// Switch to a new item without tearing down the view (next/prev episode, zapping).
    func replace(with newItem: PlaybackItem) {
        saveProgress(force: true)
        cancelRecovery()
        recoveryAttempts = 0
        pendingResumeMs = nil
        player.stop()
        item = newItem
        titleLabel.stringValue = newItem.title
        if downloadPill.superview != nil { downloadPill.item = newItem }
        slider.isHidden = newItem.isLive
        liveTag.isHidden = !newItem.isLive
        duration.isHidden = newItem.isLive
        slider.doubleValue = 0
        elapsed.stringValue = "0:00"
        updateEpisodeButtons()
        start()
    }

    private func tick(timeMs: Int64, lengthMs: Int64, state: VLCPlayer.State) {
        if state != lastLoggedState {
            Log.info("Player state \(lastLoggedState) → \(state) at \(timeMs)ms / \(lengthMs)ms (\(item.isLive ? "live" : "vod"))")
            lastLoggedState = state
        }
        if lengthMs > 0 { knownLengthMs = lengthMs }
        switch state {
        case .buffering, .opening:
            setBuffering(true)
        case .playing:
            setBuffering(false)
            errorLabel.isHidden = true
            retryButton.isHidden = true
            playPause.setSymbol("pause.fill", pointSize: 20)
            applyResumeIfNeeded(lengthMs: lengthMs)
            if didApplyResume && timeMs > 0 { lastGoodTimeMs = timeMs }
            // A recovery that has kept playing for 30s is a success: reset the budget.
            if recoveryAttempts > 0 && timeMs - recoveredAtMs > 30_000 {
                Log.info("Playback stable again after reconnect; resetting retry budget")
                recoveryAttempts = 0
            }
        case .paused:
            setBuffering(false)
            playPause.setSymbol("play.fill", pointSize: 20)
        case .error:
            setBuffering(false)
            recover(reason: "playback error")
        case .ended:
            setBuffering(false)
            if isGenuineEnd() {
                handleEnded()
            } else {
                recover(reason: "stream ended early")
            }
        default:
            break
        }

        // ±10s controls only work on seekable media; dim them otherwise.
        if !item.isLive {
            let seekable = player.isSeekable
            setEnabled(back10, seekable)
            setEnabled(forward10, seekable)
        }

        if !item.isLive && !userScrubbing {
            let total = Double(lengthMs) / 1000.0
            let cur = Double(timeMs) / 1000.0
            if total > 0 {
                slider.maxValue = total
                slider.doubleValue = cur
                duration.stringValue = formatHMS(total)
            }
            elapsed.stringValue = formatHMS(cur)
            saveProgress(force: false)
        } else if item.isLive {
            elapsed.stringValue = formatHMS(Double(timeMs) / 1000.0)
        }
    }

    /// Single source of truth for the loading overlay.
    private func setBuffering(_ on: Bool) {
        if on { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }

    private func applyResumeIfNeeded(lengthMs: Int64) {
        guard !didApplyResume else { return }
        if item.isLive { didApplyResume = true; return }
        // libVLC often reports .playing before the length is known; wait for a
        // real length so the one-shot resume isn't wasted on a lengthMs == 0 tick.
        guard lengthMs > 0 else { return }
        if let resume = pendingResumeMs {
            if resume > 1000 { player.seek(toMs: resume) }
            lastGoodTimeMs = resume
            pendingResumeMs = nil
        } else if item.resumeSecs > 10 {
            player.seek(toMs: Int64(item.resumeSecs * 1000))
        }
        didApplyResume = true
    }

    // MARK: End-of-stream & recovery

    /// True only when a movie/episode really reached its end. Live streams never "end".
    private func isGenuineEnd() -> Bool {
        if item.isLive { return false }
        let length = knownLengthMs
        // Unknown length (rare for VOD): we cannot tell, so trust libVLC.
        guard length > 0 else { return true }
        let remaining = length - lastGoodTimeMs
        return remaining <= max(30_000, length / 50)   // within 30 s or 2 % of the end
    }

    /// Reconnect after a recoverable failure, resuming at the last good position.
    /// Bounded: at most `maxRecoveryAttempts` consecutive tries with back-off,
    /// then a visible error with a Retry button — never a silent close.
    private func recover(reason: String) {
        guard !recovering, !endHandled else { return }
        guard recoveryAttempts < Self.maxRecoveryAttempts else {
            endHandled = true
            saveProgress(force: true)
            Log.error("Playback failed after \(recoveryAttempts) reconnect attempts (\(reason))")
            showFailure()
            return
        }
        recovering = true
        recoveryAttempts += 1
        let resumeMs = item.isLive ? 0 : lastGoodTimeMs
        recoveredAtMs = resumeMs
        let delay = Self.recoveryDelays[min(recoveryAttempts - 1, Self.recoveryDelays.count - 1)]
        Log.warn("Playback interrupted (\(reason)) at \(resumeMs)ms of \(knownLengthMs)ms — reconnecting in \(delay)s (attempt \(recoveryAttempts)/\(Self.maxRecoveryAttempts))")
        saveProgress(force: true)
        player.stop()
        setBuffering(true)
        showError("Connection interrupted — reconnecting… (\(recoveryAttempts)/\(Self.maxRecoveryAttempts))")
        retryButton.isHidden = true
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.recovering else { return }
            self.recovering = false
            self.pendingResumeMs = resumeMs > 0 ? resumeMs : nil
            // Reload the original URL: providers hand out a fresh (re)direct/token.
            self.start()
        }
        recoveryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelRecovery() {
        recoveryWork?.cancel()
        recoveryWork = nil
        recovering = false
    }

    private func showFailure() {
        setBuffering(false)
        player.stop()
        let message = item.isLive
            ? "This channel stopped and could not be reconnected. It may be offline, or your connection limit may be reached."
            : "Playback stopped and could not be resumed after \(Self.maxRecoveryAttempts) attempts. Check your internet connection or your provider's connection limit, then press Retry."
        showError(message)
        retryButton.isHidden = false
        setControlsHidden(false)
    }

    private func retryAfterFailure() {
        recoveryAttempts = 0
        endHandled = false
        retryButton.isHidden = true
        if !item.isLive && lastGoodTimeMs > 0 { pendingResumeMs = lastGoodTimeMs }
        start()
    }

    private func saveProgress(force: Bool) {
        guard !item.isLive else { return }
        // Until a pending resume/seek has been applied, the engine's clock is ~0 and
        // must not overwrite the saved position.
        guard didApplyResume else { return }
        let now = Date().timeIntervalSince1970
        if !force && now - lastSaved < 5 { return }
        lastSaved = now
        let t = player.timeMs
        let pos = Double(t > 0 ? t : lastGoodTimeMs) / 1000.0
        let dur = Double(player.lengthMs > 0 ? player.lengthMs : knownLengthMs) / 1000.0
        if pos > 0 { userData?.updateProgress(item.ref, position: pos, duration: dur) }
    }

    private func handleEnded() {
        guard !endHandled else { return }   // ticks keep arriving while ended
        endHandled = true
        Log.info("Playback finished at \(lastGoodTimeMs)ms of \(knownLengthMs)ms")
        saveProgress(force: true)
        if let nav = navigator, nav.hasNext, let next = nav.next() {
            replace(with: next)
        } else if !embedded {
            close()
        }
    }

    private func showError(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.isHidden = false
    }

    // MARK: Seek / episode actions

    @objc private func seekBack10() {
        guard !item.isLive, player.isSeekable else { return }
        player.seek(toMs: max(0, player.timeMs - 10_000))
        elapsed.stringValue = formatHMS(Double(player.timeMs) / 1000.0)
        revealControls()
    }

    @objc private func seekForward10() {
        guard !item.isLive, player.isSeekable else { return }
        let length = player.lengthMs
        var target = player.timeMs + 10_000
        // Never clamp below the current position (would seek backward in the last second).
        if length > 0 { target = min(target, max(player.timeMs, length - 1000)) }
        player.seek(toMs: max(0, target))
        revealControls()
    }

    @objc private func goPrevEpisode() {
        guard let nav = navigator, nav.hasPrev, let item = nav.previous() else { return }
        replace(with: item)
    }
    @objc private func goNextEpisode() {
        guard let nav = navigator, nav.hasNext, let item = nav.next() else { return }
        replace(with: item)
    }

    private func updateEpisodeButtons() {
        guard navigator != nil else { return }
        setEnabled(prevEpisode, navigator?.hasPrev == true)
        setEnabled(nextEpisode, navigator?.hasNext == true)
    }

    private func setEnabled(_ button: IconButton, _ enabled: Bool) {
        button.isEnabled = enabled
        button.alphaValue = enabled ? 1.0 : 0.35
    }

    // MARK: Transport

    @objc private func togglePlay() {
        if player.state == .paused { player.setPaused(false) }
        else if player.isPlaying { player.setPaused(true) }
        else { player.play() }
        revealControls()
    }

    @objc private func scrub() {
        userScrubbing = true
        elapsed.stringValue = formatHMS(slider.doubleValue)
        if NSApp.currentEvent?.type == .leftMouseUp {
            player.seek(toMs: Int64(slider.doubleValue * 1000))
            userScrubbing = false
        }
    }

    @objc private func volumeChanged() {
        player.volume = Int(volume.doubleValue)
        player.isMuted = volume.doubleValue == 0
        updateMuteIcon()
    }

    @objc private func toggleMute() {
        player.isMuted.toggle()
        if !player.isMuted && player.volume == 0 { player.volume = 60; volume.doubleValue = 60 }
        updateMuteIcon()
    }

    private func updateMuteIcon() {
        muteButton.setSymbol(player.isMuted || player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", pointSize: 14)
    }

    @objc private func toggleFullscreen() {
        // The embedded Live TV player hands off to a dedicated full-screen window
        // (making the whole library window full screen would keep the video small).
        if embedded, let request = onFullscreenRequest { request(); return }
        view.window?.toggleFullScreen(nil)
    }

    @objc private func close() {
        cancelRecovery()
        player.stop()
        onClose?()
    }

    @objc private func showSettings() {
        let menu = NSMenu()

        // Aspect ratio
        let aspect = NSMenuItem(title: "Aspect Ratio", action: nil, keyEquivalent: "")
        let aspectMenu = NSMenu()
        for (label, value) in [("Default", nil), ("16:9", "16:9"), ("4:3", "4:3"),
                               ("16:10", "16:10"), ("21:9", "21:9"), ("1:1", "1:1")] as [(String, String?)] {
            let mi = NSMenuItem(title: label, action: #selector(pickAspect(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = value
            mi.state = (value == aspectRatio) ? .on : .off
            aspectMenu.addItem(mi)
        }
        aspect.submenu = aspectMenu
        menu.addItem(aspect)

        // Playback speed (VOD only)
        if !item.isLive {
            let rate = NSMenuItem(title: "Playback Speed", action: nil, keyEquivalent: "")
            let rateMenu = NSMenu()
            for r in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0] {
                let mi = NSMenuItem(title: r == 1.0 ? "Normal" : "\(r)×", action: #selector(pickRate(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = r
                rateMenu.addItem(mi)
            }
            rate.submenu = rateMenu
            menu.addItem(rate)
        }

        // Audio tracks
        let audioTracks = player.audioTracks()
        if !audioTracks.isEmpty {
            let audio = NSMenuItem(title: "Audio Track", action: nil, keyEquivalent: "")
            let audioMenu = NSMenu()
            for t in audioTracks {
                let mi = NSMenuItem(title: t.name, action: #selector(pickAudio(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = t.id
                mi.state = (t.id == player.currentAudioTrack) ? .on : .off
                audioMenu.addItem(mi)
            }
            audio.submenu = audioMenu
            menu.addItem(audio)
        }

        // Subtitles
        let subs = player.subtitleTracks()
        let subItem = NSMenuItem(title: "Subtitles", action: nil, keyEquivalent: "")
        let subMenu = NSMenu()
        let off = NSMenuItem(title: "Off", action: #selector(pickSubtitle(_:)), keyEquivalent: "")
        off.target = self; off.representedObject = -1
        off.state = (player.currentSubtitleTrack == -1) ? .on : .off
        subMenu.addItem(off)
        for t in subs where t.id != -1 {
            let mi = NSMenuItem(title: t.name, action: #selector(pickSubtitle(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = t.id
            mi.state = (t.id == player.currentSubtitleTrack) ? .on : .off
            subMenu.addItem(mi)
        }
        subItem.submenu = subMenu
        menu.addItem(subItem)

        let location = NSPoint(x: 0, y: settingsButton.bounds.height + 6)
        menu.popUp(positioning: nil, at: location, in: settingsButton)
    }

    @objc private func pickAspect(_ sender: NSMenuItem) {
        aspectRatio = sender.representedObject as? String
        player.setAspectRatio(aspectRatio)
    }
    @objc private func pickRate(_ sender: NSMenuItem) {
        if let r = sender.representedObject as? Double { player.setRate(Float(r)) }
    }
    @objc private func pickAudio(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? Int { player.currentAudioTrack = id }
    }
    @objc private func pickSubtitle(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? Int { player.currentSubtitleTrack = id }
    }

    // MARK: Keyboard

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 49: togglePlay(); return true                 // space
        case 123: seekBack10(); return true                // ←
        case 124: seekForward10(); return true             // →
        case 126: adjustVolume(+5); return true            // ↑
        case 125: adjustVolume(-5); return true            // ↓
        case 3:  toggleFullscreen(); return true           // f
        case 46: toggleMute(); return true                 // m
        case 53: if view.window?.styleMask.contains(.fullScreen) == true { toggleFullscreen() } else if !embedded { close() }; return true // esc
        default: return false
        }
    }

    private func adjustVolume(_ delta: Int) {
        let v = min(125, max(0, player.volume + delta))
        player.volume = v
        volume.doubleValue = Double(v)
        updateMuteIcon()
        revealControls()
    }

    // MARK: Control auto-hide

    private func revealControls() {
        setControlsHidden(false)
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.player.isPlaying else { return }
            self.setControlsHidden(true)
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }

    private func setControlsHidden(_ hidden: Bool) {
        let alpha: CGFloat = hidden ? 0 : 1
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            topBar.animator().alphaValue = alpha
            bottomBar.animator().alphaValue = alpha
        }
        NSCursor.setHiddenUntilMouseMoves(hidden)
    }
}
