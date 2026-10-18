import Foundation

/// A fully-resolved thing to hand the player.
struct PlaybackItem {
    let ref: MediaRef
    let url: URL
    let title: String
    let isLive: Bool
    let resumeSecs: Double
    let networkCaching: Int

    var mediaOptions: [String] {
        var opts = [":network-caching=\(networkCaching)"]
        if isLive {
            opts.append(":live-caching=\(networkCaching)")
            opts.append(":clock-jitter=0")
        }
        return opts
    }
}

/// Builds PlaybackItems from the current session (URLs need the client's creds).
extension Session {
    func makeLiveItem(_ s: LiveStream) -> PlaybackItem? {
        guard let url = client.liveURL(streamID: s.streamID, format: profile.liveFormat) else { return nil }
        return PlaybackItem(ref: .live(s), url: url, title: s.name, isLive: true,
                            resumeSecs: 0, networkCaching: 1500)
    }

    func makeMovieItem(_ s: VODStream, ext: String?) -> PlaybackItem? {
        let container = ext ?? s.containerExtension ?? "mp4"
        guard let url = client.movieURL(streamID: s.streamID, ext: container) else { return nil }
        let ref = MediaRef.movie(s)
        return PlaybackItem(ref: ref, url: url, title: s.name, isLive: false,
                            resumeSecs: userData.resumePosition(for: ref), networkCaching: 3000)
    }

    func makeEpisodeItem(_ e: Episode, series: SeriesStream) -> PlaybackItem? {
        let container = e.containerExtension ?? "mp4"
        guard let url = client.episodeURL(episodeID: e.id, ext: container) else { return nil }
        let ref = MediaRef.episode(e, series: series)
        let title = "\(series.name) · S\(e.season)E\(e.episodeNum) \(e.title)"
        return PlaybackItem(ref: ref, url: url, title: title, isLive: false,
                            resumeSecs: userData.resumePosition(for: ref), networkCaching: 3000)
    }

    /// Rebuild a playable item from a stored reference (resume / favorites / recents).
    func makeItem(from ref: MediaRef) -> PlaybackItem? {
        switch ref.kind {
        case .live:
            guard let id = ref.streamID, let url = client.liveURL(streamID: id, format: profile.liveFormat) else { return nil }
            return PlaybackItem(ref: ref, url: url, title: ref.title, isLive: true, resumeSecs: 0, networkCaching: 1500)
        case .movie:
            guard let id = ref.streamID,
                  let url = client.movieURL(streamID: id, ext: ref.containerExt ?? "mp4") else { return nil }
            return PlaybackItem(ref: ref, url: url, title: ref.title, isLive: false,
                                resumeSecs: userData.resumePosition(for: ref), networkCaching: 3000)
        case .episode:
            guard let eid = ref.episodeID,
                  let url = client.episodeURL(episodeID: eid, ext: ref.containerExt ?? "mp4") else { return nil }
            return PlaybackItem(ref: ref, url: url, title: ref.title, isLive: false,
                                resumeSecs: userData.resumePosition(for: ref), networkCaching: 3000)
        }
    }
}
