package com.iptvxtreme.player.ui.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.iptvxtreme.player.core.AppState
import com.iptvxtreme.player.core.MediaRef
import com.iptvxtreme.player.ui.AppCoordinator
import com.iptvxtreme.player.ui.LocalCoordinator
import com.iptvxtreme.player.ui.components.EmptyStateView
import com.iptvxtreme.player.ui.components.LoadingView
import com.iptvxtreme.player.ui.components.PosterCard
import com.iptvxtreme.player.ui.components.Rail
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope

/**
 * Dashboard: Continue Watching, Recent Channels, Favorites, and freshly-added
 * Movies and Series. Each rail is skipped when empty.
 */
@Composable
fun HomeScreen() {
    val session = AppState.session ?: return
    val coordinator = LocalCoordinator.current
    val user = session.userData
    var loading by remember { mutableStateOf(session.allMovies.isEmpty() && session.allSeries.isEmpty()) }

    LaunchedEffect(coordinator.refreshTick) {
        val force = coordinator.refreshTick > 0
        if (force) loading = true
        coroutineScope {
            val a = async { runCatching { session.loadAllMovies(force) } }
            val b = async { runCatching { session.loadAllSeries(force) } }
            val c = async { runCatching { session.loadAllLive(force) } }
            a.await(); b.await(); c.await()
        }
        loading = false
    }

    @Suppress("UNUSED_VARIABLE") val rev = user.revision   // recompose when favorites/history change
    val resume = remember(rev) { user.continueWatching() }
    val recentChannels = remember(rev, session.allLive) {
        val byID = session.allLive.associateBy { it.streamID }
        user.recentChannelIDs.mapNotNull { byID[it] }.take(12)
    }
    val favorites = remember(rev) { user.favorites.take(14) }
    val newMovies = remember(session.allMovies) { session.allMovies.sortedByDescending { it.addedTimestamp ?: 0 }.take(16) }
    val newSeries = remember(session.allSeries) { session.allSeries.sortedByDescending { it.lastModified ?: 0 }.take(16) }

    val nothing = resume.isEmpty() && recentChannels.isEmpty() && favorites.isEmpty() && newMovies.isEmpty() && newSeries.isEmpty()
    if (nothing) {
        if (loading) LoadingView() else EmptyStateView(Icons.Default.AutoAwesome, "Nothing here yet",
            "Browse Live TV, Movies, or Series to start watching. Your favorites and history will appear here.")
        return
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top = 8.dp)) {
        if (resume.isNotEmpty()) Rail("Continue Watching", resume, key = { it.ref.key }) { e ->
            PosterCard(e.ref.title, "Resume", e.ref.poster, if (e.ref.kind == MediaRef.Kind.live) Icons.Default.Tv else Icons.Default.Movie,
                progress = e.progressFraction) { coordinator.play(e.ref) }
        }
        if (recentChannels.isNotEmpty()) Rail("Recent Channels", recentChannels, key = { it.streamID }) { ch ->
            PosterCard(ch.name, null, ch.icon, Icons.Default.Tv, aspect = 1f) { coordinator.play(MediaRef.live(ch)) }
        }
        if (favorites.isNotEmpty()) Rail("Your Favorites", favorites, key = { it.key }) { ref ->
            PosterCard(ref.title, null, ref.poster, if (ref.kind == MediaRef.Kind.live) Icons.Default.Tv else Icons.Default.Movie,
                aspect = if (ref.kind == MediaRef.Kind.live) 1f else 2f / 3f) { openFavorite(coordinator, ref) }
        }
        if (newMovies.isNotEmpty()) Rail("Recently Added Movies", newMovies, key = { it.streamID }) { m ->
            PosterCard(m.name, null, m.icon, Icons.Default.Movie, badge = m.rating5?.let { "%.1f".format(it) }) { coordinator.openMovie(m) }
        }
        if (newSeries.isNotEmpty()) Rail("Recently Added Series", newSeries, key = { it.seriesID }) { s ->
            PosterCard(s.name, null, s.cover, Icons.Default.VideoLibrary, badge = s.rating5?.let { "%.1f".format(it) }) { coordinator.openSeries(s) }
        }
    }
}

/** Favorites open their detail page when we can resolve them, otherwise play directly. */
fun openFavorite(coordinator: AppCoordinator, ref: MediaRef) {
    val session = AppState.session ?: return
    when {
        ref.isSeriesFavorite -> session.allSeries.firstOrNull { it.seriesID == ref.seriesID }?.let { coordinator.openSeries(it) }
        ref.kind == MediaRef.Kind.movie ->
            session.allMovies.firstOrNull { it.streamID == ref.streamID }?.let { coordinator.openMovie(it) } ?: coordinator.play(ref)
        else -> coordinator.play(ref)
    }
}
