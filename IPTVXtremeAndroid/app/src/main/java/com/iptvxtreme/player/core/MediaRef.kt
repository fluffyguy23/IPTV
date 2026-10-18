package com.iptvxtreme.player.core

import kotlinx.serialization.Serializable

/**
 * A provider-independent reference to something playable. Carries just enough
 * to rebuild a playback URL later (for resume / favorites / history) without
 * storing the full stream object — and never the credentials.
 */
@Serializable
data class MediaRef(
    val kind: Kind,
    val streamID: Long? = null,      // live & movie
    val episodeID: String? = null,   // episode
    val containerExt: String? = null,// movie / episode
    val seriesID: Long? = null,      // for episodes: parent series
    val title: String,
    val poster: String? = null,
) {
    @Serializable
    enum class Kind { live, movie, episode }

    /** Stable identity for favorites/history dedup. */
    val key: String get() = when (kind) {
        Kind.live -> "live:${streamID ?: -1}"
        Kind.movie -> "movie:${streamID ?: -1}"
        Kind.episode -> "episode:${episodeID ?: "?"}"
    }

    val isResumable: Boolean get() = kind != Kind.live && !isSeriesFavorite

    /** Series are favorited at the show level with a synthetic "series-<id>" episode id. */
    val isSeriesFavorite: Boolean get() = episodeID?.startsWith("series-") == true

    companion object {
        fun live(s: LiveStream) = MediaRef(Kind.live, streamID = s.streamID, title = s.name, poster = s.icon)
        fun movie(s: VODStream) = MediaRef(Kind.movie, streamID = s.streamID, containerExt = s.containerExtension,
            title = s.name, poster = s.icon)
        fun episode(e: Episode, series: SeriesStream) = MediaRef(Kind.episode, episodeID = e.id,
            containerExt = e.containerExtension, seriesID = series.seriesID,
            title = "${series.name} · S${e.season}E${e.episodeNum}", poster = e.image ?: series.cover)
        fun series(s: SeriesStream) = MediaRef(Kind.episode, episodeID = "series-${s.seriesID}",
            seriesID = s.seriesID, title = s.name, poster = s.cover)
    }
}

@Serializable
data class HistoryEntry(
    val ref: MediaRef,
    val positionSecs: Double,
    val durationSecs: Double,
    val lastPlayed: Long,
) {
    /** Considered "finished" when within 60s of the end (or past 95%). */
    val isFinished: Boolean get() =
        durationSecs > 0 && (positionSecs >= durationSecs - 60 || positionSecs / durationSecs >= 0.95)

    val progressFraction: Float get() =
        if (durationSecs <= 0) 0f else (positionSecs / durationSecs).coerceIn(0.0, 1.0).toFloat()
}
