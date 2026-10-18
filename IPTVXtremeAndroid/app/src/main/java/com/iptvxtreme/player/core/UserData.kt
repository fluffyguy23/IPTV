package com.iptvxtreme.player.core

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import com.iptvxtreme.player.IPTVApp
import kotlinx.serialization.Serializable
import java.io.File

/**
 * Per-profile favorites, watch history (with resume points), and recent
 * channels. Persisted as JSON under files/UserData/<profileID>.json.
 * Reading [revision] inside a composable makes it recompose on any change.
 */
class UserData(profileID: String) {
    @Serializable
    private data class Store(
        val favorites: List<MediaRef> = emptyList(),
        val history: List<HistoryEntry> = emptyList(),
        val recentChannels: List<Long> = emptyList(),
    )

    private val file = File(File(IPTVApp.instance.noBackupFilesDir, "UserData").apply { mkdirs() }, "$profileID.json")

    var revision by mutableIntStateOf(0)
        private set

    private var store: Store = runCatching {
        XtreamClient.json.decodeFromString(Store.serializer(), file.readText())
    }.getOrDefault(Store())

    private fun update(transform: (Store) -> Store) = synchronized(this) {
        store = transform(store)
        runCatching {
            val tmp = File(file.parentFile, file.name + ".tmp")
            tmp.writeText(XtreamClient.json.encodeToString(Store.serializer(), store))
            if (!tmp.renameTo(file)) { file.delete(); tmp.renameTo(file) }
        }
        revision++
    }

    // MARK: Favorites

    val favorites: List<MediaRef> get() = store.favorites

    fun isFavorite(ref: MediaRef) = store.favorites.any { it.key == ref.key }

    fun toggleFavorite(ref: MediaRef): Boolean {
        val wasFav = isFavorite(ref)
        update { s ->
            s.copy(favorites = if (wasFav) s.favorites.filterNot { it.key == ref.key } else listOf(ref) + s.favorites)
        }
        return !wasFav
    }

    fun favorites(kind: MediaRef.Kind) = store.favorites.filter { it.kind == kind && !it.isSeriesFavorite }

    val seriesFavorites: List<MediaRef> get() = store.favorites.filter { it.isSeriesFavorite }

    // MARK: History & resume

    val history: List<HistoryEntry> get() = store.history.sortedByDescending { it.lastPlayed }

    /** Items worth resuming on the Home screen (unfinished movies/episodes). */
    fun continueWatching(limit: Int = 20) =
        history.filter { it.ref.isResumable && !it.isFinished && it.positionSecs > 10 }.take(limit)

    fun resumePosition(ref: MediaRef): Double {
        val e = store.history.firstOrNull { it.ref.key == ref.key } ?: return 0.0
        return if (e.isFinished) 0.0 else e.positionSecs
    }

    /** Record that playback started (updates recents; seeds a history row). */
    fun recordPlay(ref: MediaRef) = update { s ->
        var recents = s.recentChannels
        if (ref.kind == MediaRef.Kind.live && ref.streamID != null) {
            recents = (listOf(ref.streamID) + recents.filterNot { it == ref.streamID }).take(40)
        }
        val now = System.currentTimeMillis()
        val existing = s.history.firstOrNull { it.ref.key == ref.key }
        val history = if (existing != null) {
            s.history.map { if (it.ref.key == ref.key) it.copy(ref = ref, lastPlayed = now) else it }
        } else {
            listOf(HistoryEntry(ref, 0.0, 0.0, now)) + s.history
        }
        s.copy(recentChannels = recents, history = history.sortedByDescending { it.lastPlayed }.take(200))
    }

    /** Update resume position during playback (called periodically). */
    fun updateProgress(ref: MediaRef, position: Double, duration: Double) {
        if (!ref.isResumable) return
        update { s ->
            val now = System.currentTimeMillis()
            val history = if (s.history.any { it.ref.key == ref.key }) {
                s.history.map {
                    if (it.ref.key == ref.key) it.copy(positionSecs = position,
                        durationSecs = if (duration > 0) duration else it.durationSecs, lastPlayed = now) else it
                }
            } else {
                listOf(HistoryEntry(ref, position, duration, now)) + s.history
            }
            s.copy(history = history)
        }
    }

    val recentChannelIDs: List<Long> get() = store.recentChannels

    /**
     * Remove a single item from history (and recent channels), including its
     * saved resume/progress. Does not touch favorites.
     */
    fun removeHistory(ref: MediaRef) = update { s ->
        s.copy(
            history = s.history.filterNot { it.ref.key == ref.key },
            recentChannels = if (ref.kind == MediaRef.Kind.live) s.recentChannels.filterNot { it == ref.streamID } else s.recentChannels,
        )
    }

    fun clearHistory() = update { it.copy(history = emptyList(), recentChannels = emptyList()) }
}
