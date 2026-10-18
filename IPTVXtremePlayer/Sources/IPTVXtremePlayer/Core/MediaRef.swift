import Foundation

/// A provider-independent reference to something playable. Carries just enough
/// to rebuild a playback URL later (for resume / favorites / history) without
/// storing the full stream object.
struct MediaRef: Codable, Hashable {
    enum Kind: String, Codable { case live, movie, episode }

    var kind: Kind
    var streamID: Int?        // live & movie
    var episodeID: String?    // episode
    var containerExt: String? // movie / episode
    var seriesID: Int?        // for episodes: parent series
    var title: String
    var poster: String?

    /// Stable identity for favorites/history dedup.
    var key: String {
        switch kind {
        case .live:    return "live:\(streamID ?? -1)"
        case .movie:   return "movie:\(streamID ?? -1)"
        case .episode: return "episode:\(episodeID ?? "?")"
        }
    }

    var isResumable: Bool { kind != .live }

    // Convenience constructors
    static func live(_ s: LiveStream) -> MediaRef {
        MediaRef(kind: .live, streamID: s.streamID, episodeID: nil, containerExt: nil,
                 seriesID: nil, title: s.name, poster: s.icon)
    }
    static func movie(_ s: VODStream) -> MediaRef {
        MediaRef(kind: .movie, streamID: s.streamID, episodeID: nil,
                 containerExt: s.containerExtension, seriesID: nil, title: s.name, poster: s.icon)
    }
    static func episode(_ e: Episode, series: SeriesStream) -> MediaRef {
        MediaRef(kind: .episode, streamID: nil, episodeID: e.id,
                 containerExt: e.containerExtension, seriesID: series.seriesID,
                 title: "\(series.name) · S\(e.season)E\(e.episodeNum)", poster: e.image ?? series.cover)
    }
    static func series(_ s: SeriesStream) -> MediaRef {
        // Series are favorited at the show level using the seriesID.
        MediaRef(kind: .episode, streamID: nil, episodeID: "series-\(s.seriesID)",
                 containerExt: nil, seriesID: s.seriesID, title: s.name, poster: s.cover)
    }
}

struct HistoryEntry: Codable, Hashable {
    var ref: MediaRef
    var positionSecs: Double
    var durationSecs: Double
    var lastPlayed: Date

    /// Considered "finished" when within 60s of the end (or past 95%).
    var isFinished: Bool {
        guard durationSecs > 0 else { return false }
        return positionSecs >= durationSecs - 60 || (positionSecs / durationSecs) >= 0.95
    }

    var progressFraction: Double {
        guard durationSecs > 0 else { return 0 }
        return min(1, max(0, positionSecs / durationSecs))
    }
}
