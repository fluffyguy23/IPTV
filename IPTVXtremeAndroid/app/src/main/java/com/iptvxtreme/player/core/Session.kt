package com.iptvxtreme.player.core

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import java.io.File

/**
 * A live, authenticated connection to one provider, plus a cached content
 * repository. All content fetches go through here so caching and the in-memory
 * search index are shared across the UI.
 */
class Session(val profile: Profile, val client: XtreamClient, val auth: AuthResponse) {
    val userData = UserData(profile.id)
    private val cache = DataCache(profile.id)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // In-memory indexes (populated lazily; used for search, Home rails & favorite resolution).
    var allLive by mutableStateOf<List<LiveStream>>(emptyList()); private set
    var allMovies by mutableStateOf<List<VODStream>>(emptyList()); private set
    var allSeries by mutableStateOf<List<SeriesStream>>(emptyList()); private set

    private val cacheTTL = 6 * 3600 * 1000L

    // MARK: Generic cached loader

    private suspend fun <T> cached(key: String, action: String, forceRefresh: Boolean, parse: (JsonObject) -> T): List<T> =
        withContext(Dispatchers.IO) {
            val file: File = cache.fresh(key, if (forceRefresh) 0 else cacheTTL) ?: try {
                client.download(action, cache.file(key))
                cache.file(key)
            } catch (e: XtreamError) {
                // Fall back to any stale cache when the network fails.
                cache.fresh(key, null) ?: throw e
            }
            try {
                XtreamClient.parseList(file.inputStream(), parse)
            } catch (e: XtreamError) {
                file.delete()  // a corrupt cache must not stick around
                throw e
            }
        }

    // MARK: Categories

    suspend fun liveCategories(forceRefresh: Boolean = false) =
        cached("live_cats", "get_live_categories", forceRefresh, Category::parse)
    suspend fun movieCategories(forceRefresh: Boolean = false) =
        cached("vod_cats", "get_vod_categories", forceRefresh, Category::parse)
    suspend fun seriesCategories(forceRefresh: Boolean = false) =
        cached("series_cats", "get_series_categories", forceRefresh, Category::parse)

    // MARK: Streams (full lists, indexed for search)

    // One lock per list so concurrent callers (warm-up + a screen) parse it only once.
    private val liveLock = Mutex()
    private val moviesLock = Mutex()
    private val seriesLock = Mutex()

    suspend fun loadAllLive(forceRefresh: Boolean = false): List<LiveStream> = liveLock.withLock {
        if (!forceRefresh && allLive.isNotEmpty()) return allLive
        val list = cached("live_all", "get_live_streams", forceRefresh, LiveStream::parse).distinctBy { it.streamID }
        withContext(Dispatchers.Main) { allLive = list }
        list
    }
    suspend fun loadAllMovies(forceRefresh: Boolean = false): List<VODStream> = moviesLock.withLock {
        if (!forceRefresh && allMovies.isNotEmpty()) return allMovies
        val list = cached("vod_all", "get_vod_streams", forceRefresh, VODStream::parse).distinctBy { it.streamID }
        withContext(Dispatchers.Main) { allMovies = list }
        list
    }
    suspend fun loadAllSeries(forceRefresh: Boolean = false): List<SeriesStream> = seriesLock.withLock {
        if (!forceRefresh && allSeries.isNotEmpty()) return allSeries
        val list = cached("series_all", "get_series", forceRefresh, SeriesStream::parse).distinctBy { it.seriesID }
        withContext(Dispatchers.Main) { allSeries = list }
        list
    }

    // MARK: Detail

    suspend fun vodInfo(id: Long) = client.vodInfo(id)
    suspend fun seriesInfo(id: Long) = client.seriesInfo(id)

    // MARK: Search (across cached indexes)

    data class SearchResults(val live: List<LiveStream>, val movies: List<VODStream>, val series: List<SeriesStream>) {
        val isEmpty get() = live.isEmpty() && movies.isEmpty() && series.isEmpty()
    }

    fun search(query: String, limitPerSection: Int = 60): SearchResults {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return SearchResults(emptyList(), emptyList(), emptyList())
        return SearchResults(
            live = allLive.asSequence().filter { it.name.lowercase().contains(q) }.take(limitPerSection).toList(),
            movies = allMovies.asSequence().filter { it.name.lowercase().contains(q) }.take(limitPerSection).toList(),
            series = allSeries.asSequence().filter { it.name.lowercase().contains(q) }.take(limitPerSection).toList(),
        )
    }

    /** Warm the search indexes in the background after connecting. */
    fun warmIndexes() {
        scope.launch {
            runCatching { loadAllLive() }
            runCatching { loadAllMovies() }
            runCatching { loadAllSeries() }
        }
    }

    fun clearCaches() = cache.clear()

    fun close() = scope.cancel()
}
