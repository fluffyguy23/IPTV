import Foundation

/// Tracks position within a series' episodes (flattened across all seasons in
/// order) so the player can offer Previous / Next episode navigation and
/// auto-advance. Cross-season boundaries are handled because the list is the
/// whole series in (season, episode) order.
final class EpisodeNavigator {
    private let session: Session
    private let series: SeriesStream
    private let episodes: [Episode]
    private(set) var index: Int

    init(session: Session, series: SeriesStream, episodes: [Episode], startIndex: Int) {
        self.session = session
        self.series = series
        self.episodes = episodes
        self.index = max(0, min(startIndex, episodes.count - 1))
    }

    /// Build a navigator spanning the whole series, positioned at `episode`.
    static func forSeries(_ series: SeriesStream, info: SeriesInfo, startingAt episode: Episode,
                          session: Session) -> EpisodeNavigator {
        var flat: [Episode] = []
        for season in info.sortedSeasons {
            flat.append(contentsOf: info.episodesBySeason[season] ?? [])
        }
        let start = flat.firstIndex(where: { $0.id == episode.id }) ?? 0
        return EpisodeNavigator(session: session, series: series, episodes: flat, startIndex: start)
    }

    var hasNext: Bool { index + 1 < episodes.count }
    var hasPrev: Bool { index - 1 >= 0 }
    var count: Int { episodes.count }

    func currentItem() -> PlaybackItem? {
        guard episodes.indices.contains(index) else { return nil }
        return session.makeEpisodeItem(episodes[index], series: series)
    }

    func next() -> PlaybackItem? {
        guard hasNext else { return nil }
        let candidate = index + 1
        guard let item = session.makeEpisodeItem(episodes[candidate], series: series) else { return nil }
        index = candidate   // commit only after the item is known-buildable
        return item
    }

    func previous() -> PlaybackItem? {
        guard hasPrev else { return nil }
        let candidate = index - 1
        guard let item = session.makeEpisodeItem(episodes[candidate], series: series) else { return nil }
        index = candidate
        return item
    }
}
