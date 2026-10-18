import AppKit

/// Swift wrapper over the libVLC C bridge. One instance per active playback view.
final class VLCPlayer {
    struct Track: Hashable { let id: Int; let name: String }
    enum State: Int { case nothing, opening, buffering, playing, paused, stopped, ended, error }

    private let handle: OpaquePointer?
    private var ticker: Timer?

    /// Called ~4×/sec on the main thread with (timeMs, lengthMs, state).
    var onTick: ((Int64, Int64, State) -> Void)?

    private static var engineReady = false

    /// Initialize the shared libVLC engine once. `pluginPath` points at the
    /// VLC plugins directory (bundled, or the installed VLC.app).
    @discardableResult
    static func bootEngine(pluginPath: String?, verbose: Bool = false) -> Bool {
        if engineReady { return true }
        engineReady = vb_global_init(pluginPath, verbose)
        return engineReady
    }

    static var version: String { String(cString: vb_version()) }

    init() {
        handle = vb_player_create()
    }

    deinit {
        ticker?.invalidate()
        vb_player_destroy(handle)
    }

    func attach(to view: NSView) {
        let ptr = Unmanaged.passUnretained(view).toOpaque()
        vb_player_set_drawable(handle, ptr)
    }

    func load(url: URL, options: [String] = []) {
        if options.isEmpty {
            vb_player_set_media_url(handle, url.absoluteString, nil, 0)
        } else {
            var cStrings = options.map { strdup($0) }
            cStrings.withUnsafeMutableBufferPointer { buf in
                buf.baseAddress!.withMemoryRebound(to: Optional<UnsafePointer<CChar>>.self, capacity: buf.count) { p in
                    vb_player_set_media_url(handle, url.absoluteString, p, Int32(buf.count))
                }
            }
            cStrings.forEach { free($0) }
        }
    }

    func play() { vb_player_play(handle); startTicker() }
    func setPaused(_ paused: Bool) { vb_player_set_paused(handle, paused) }
    func stop() { vb_player_stop(handle); stopTicker() }

    var isPlaying: Bool { vb_player_is_playing(handle) }
    var isSeekable: Bool { vb_player_is_seekable(handle) }
    var state: State { State(rawValue: Int(vb_player_get_state(handle).rawValue)) ?? .nothing }

    var timeMs: Int64 { vb_player_get_time(handle) }
    var lengthMs: Int64 { vb_player_get_length(handle) }
    func seek(toMs ms: Int64) { vb_player_set_time(handle, ms) }
    var position: Float { get { vb_player_get_position(handle) } set { vb_player_set_position(handle, newValue) } }

    var volume: Int { get { Int(vb_player_get_volume(handle)) } set { vb_player_set_volume(handle, Int32(newValue)) } }
    var isMuted: Bool { get { vb_player_get_mute(handle) } set { vb_player_set_mute(handle, newValue) } }
    func setRate(_ r: Float) { vb_player_set_rate(handle, r) }
    func setAspectRatio(_ ratio: String?) { vb_player_set_aspect_ratio(handle, ratio) }

    // MARK: Tracks

    func audioTracks() -> [Track] { tracks(count: Int(vb_player_audio_track_count(handle)), audio: true) }
    func subtitleTracks() -> [Track] { tracks(count: Int(vb_player_spu_count(handle)), audio: false) }

    private func tracks(count: Int, audio: Bool) -> [Track] {
        var result: [Track] = []
        var buf = [CChar](repeating: 0, count: 256)
        for i in 0..<max(0, count) {
            var id: Int32 = -1
            let ok = buf.withUnsafeMutableBufferPointer { p -> Bool in
                if audio {
                    return vb_player_audio_track_at(handle, Int32(i), &id, p.baseAddress, 256)
                } else {
                    return vb_player_spu_at(handle, Int32(i), &id, p.baseAddress, 256)
                }
            }
            if ok {
                let name = String(cString: buf)
                result.append(Track(id: Int(id), name: name.isEmpty ? "Track \(i + 1)" : name))
            }
        }
        return result
    }

    var currentAudioTrack: Int { get { Int(vb_player_get_audio_track(handle)) } set { vb_player_set_audio_track(handle, Int32(newValue)) } }
    var currentSubtitleTrack: Int { get { Int(vb_player_get_spu(handle)) } set { vb_player_set_spu(handle, Int32(newValue)) } }

    // MARK: Ticker

    private func startTicker() {
        guard ticker == nil else { return }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.onTick?(self.timeMs, self.lengthMs, self.state)
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}
