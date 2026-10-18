package com.iptvxtreme.player.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.vector.ImageVector
import com.iptvxtreme.player.core.AppState
import com.iptvxtreme.player.core.MediaRef
import com.iptvxtreme.player.core.SeriesStream
import com.iptvxtreme.player.core.VODStream
import com.iptvxtreme.player.player.EpisodeNavigator
import com.iptvxtreme.player.player.PlaybackItem
import com.iptvxtreme.player.player.makeItem

enum class Section(val title: String, val icon: ImageVector) {
    Home("Home", Icons.Filled.Home),
    LiveTV("Live TV", Icons.Filled.Tv),
    Movies("Movies", Icons.Filled.Movie),
    Series("Series", Icons.Filled.VideoLibrary),
    Favorites("Favorites", Icons.Filled.Star),
    Recent("Recently Watched", Icons.Filled.Schedule),
    Settings("Settings", Icons.Filled.Settings),
}

sealed interface Route {
    data class Root(val section: Section) : Route
    data class MovieDetail(val movie: VODStream) : Route
    data class SeriesDetail(val series: SeriesStream) : Route
    data class Search(val query: String) : Route
}

/**
 * Lets screens drive navigation, detail pushes, playback, and section switching
 * without knowing about the activity (the macOS AppCoordinator).
 */
class AppCoordinator(
    private val launchPlayer: (PlaybackItem, EpisodeNavigator?) -> Unit,
    private val showError: (String) -> Unit,
) {
    var section by mutableStateOf(Section.Home); private set
    val stack = mutableStateListOf<Route>(Route.Root(Section.Home))
    /** Bumped by the top-bar Refresh button; screens force-reload when it changes. */
    var refreshTick by mutableIntStateOf(0); private set

    val top: Route get() = stack.last()
    val canPop: Boolean get() = stack.size > 1

    fun selectSection(s: Section) {
        section = s
        stack.clear()
        stack.add(Route.Root(s))
    }

    fun push(route: Route) { stack.add(route) }

    fun pop(): Boolean {
        if (stack.size <= 1) return false
        stack.removeAt(stack.lastIndex)
        return true
    }

    fun openMovie(movie: VODStream) = push(Route.MovieDetail(movie))
    fun openSeries(series: SeriesStream) = push(Route.SeriesDetail(series))

    fun performSearch(query: String) {
        val q = query.trim()
        if (q.isEmpty()) return
        stack.clear()
        stack.add(Route.Search(q))
    }

    fun refresh() { refreshTick++ }

    /** Open a movie/episode/channel in the full-screen player. */
    fun playInPlayer(item: PlaybackItem, navigator: EpisodeNavigator? = null) = launchPlayer(item, navigator)

    /** Play a stored reference (resume/favorites/recent), resolving its kind. */
    fun play(ref: MediaRef) {
        val session = AppState.session ?: return
        val item = session.makeItem(ref)
        if (item == null) showError("This item can no longer be played.") else launchPlayer(item, null)
    }

    fun error(message: String) = showError(message)
}

val LocalCoordinator = staticCompositionLocalOf<AppCoordinator> { error("No coordinator") }
