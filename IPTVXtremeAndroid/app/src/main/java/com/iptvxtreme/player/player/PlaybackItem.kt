package com.iptvxtreme.player.player

import com.iptvxtreme.player.core.Episode
import com.iptvxtreme.player.core.LiveStream
import com.iptvxtreme.player.core.MediaRef
import com.iptvxtreme.player.core.SeriesInfo
import com.iptvxtreme.player.core.SeriesStream
import com.iptvxtreme.player.core.Session
import com.iptvxtreme.player.core.VODStream

/** A fully-resolved thing to hand the player. Lives only in memory (the URL embeds credentials). */
data class PlaybackItem(
    val ref: MediaRef,
    val url: String,
    val title: String,
    val isLive: Boolean,
    val resumeSecs: Double,
    val networkCaching: Int,
) {
    val mediaOptions: List<String> get() = buildList {
        add(":network-caching=$networkCaching")
        add(":http-user-agent=IPTVXtremePlayer/1.1 (Android)")
        add(":http-reconnect")
        if (isLive) {
            add(":live-caching=$networkCaching")
            add(":clock-jitter=0")
        }
    }
}

/** Builds PlaybackItems from the current session (URLs need the client's creds). */
fun Session.makeLiveItem(s: LiveStream) = PlaybackItem(
    ref = MediaRef.live(s), url = client.liveURL(s.streamID, profile.liveFormat),
    title = s.name, isLive = true, resumeSecs = 0.0, networkCaching = 1500,
)

fun Session.makeMovieItem(s: VODStream, ext: String?): PlaybackItem {
    val ref = MediaRef.movie(s)
    return PlaybackItem(ref, client.movieURL(s.streamID, ext ?: s.containerExtension), s.name,
        isLive = false, resumeSecs = userData.resumePosition(ref), networkCaching = 3000)
}

fun Session.makeEpisodeItem(e: Episode, series: SeriesStream): PlaybackItem {
    val ref = MediaRef.episode(e, series)
    val title = "${series.name} · S${e.season}E${e.episodeNum} ${e.title}".trim()
    return PlaybackItem(ref, client.episodeURL(e.id, e.containerExtension), title,
        isLive = false, resumeSecs = userData.resumePosition(ref), networkCaching = 3000)
}

/** Rebuild a playable item from a stored reference (resume / favorites / recents). */
fun Session.makeItem(ref: MediaRef): PlaybackItem? = when (ref.kind) {
    MediaRef.Kind.live -> ref.streamID?.let {
        PlaybackItem(ref, client.liveURL(it, profile.liveFormat), ref.title, true, 0.0, 1500)
    }
    MediaRef.Kind.movie -> ref.streamID?.let {
        PlaybackItem(ref, client.movieURL(it, ref.containerExt), ref.title, false, userData.resumePosition(ref), 3000)
    }
    MediaRef.Kind.episode -> ref.episodeID?.takeIf { !ref.isSeriesFavorite }?.let {
        PlaybackItem(ref, client.episodeURL(it, ref.containerExt), ref.title, false, userData.resumePosition(ref), 3000)
    }
}

/**
 * Tracks position within a series' episodes (flattened across all seasons in
 * order) so the player can offer Previous / Next episode navigation and
 * auto-advance across season boundaries.
 */
class EpisodeNavigator(
    private val session: Session,
    private val series: SeriesStream,
    private val episodes: List<Episode>,
    startIndex: Int,
) {
    var index = startIndex.coerceIn(0, (episodes.size - 1).coerceAtLeast(0))
        private set

    val hasNext get() = index + 1 < episodes.size
    val hasPrev get() = index - 1 >= 0

    fun currentItem(): PlaybackItem? = episodes.getOrNull(index)?.let { session.makeEpisodeItem(it, series) }

    fun next(): PlaybackItem? {
        if (!hasNext) return null
        val item = session.makeEpisodeItem(episodes[index + 1], series)
        index += 1   // commit only after the item is built
        return item
    }

    fun previous(): PlaybackItem? {
        if (!hasPrev) return null
        val item = session.makeEpisodeItem(episodes[index - 1], series)
        index -= 1
        return item
    }

    companion object {
        /** Build a navigator spanning the whole series, positioned at `episode`. */
        fun forSeries(series: SeriesStream, info: SeriesInfo, startingAt: Episode, session: Session): EpisodeNavigator {
            val flat = info.sortedSeasons.flatMap { info.episodesBySeason[it].orEmpty() }
            val start = flat.indexOfFirst { it.id == startingAt.id }.coerceAtLeast(0)
            return EpisodeNavigator(session, series, flat, start)
        }
    }
}
