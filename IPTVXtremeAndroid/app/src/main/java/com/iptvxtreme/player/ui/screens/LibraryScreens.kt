package com.iptvxtreme.player.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.iptvxtreme.player.core.AppState
import com.iptvxtreme.player.core.MediaRef
import com.iptvxtreme.player.player.VlcPlayer
import com.iptvxtreme.player.ui.LocalCoordinator
import com.iptvxtreme.player.ui.Theme
import com.iptvxtreme.player.ui.components.Card
import com.iptvxtreme.player.ui.components.EmptyStateView
import com.iptvxtreme.player.ui.components.LoadingView
import com.iptvxtreme.player.ui.components.MenuAction
import com.iptvxtreme.player.ui.components.PillButton
import com.iptvxtreme.player.ui.components.PosterCard
import com.iptvxtreme.player.ui.components.Rail
import com.iptvxtreme.player.ui.components.SearchBox
import coil.imageLoader
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import java.text.DateFormat
import java.util.Date

// MARK: - Favorites

/** Favorites grouped into Channels, Movies, and Series rails. Long-press to remove. */
@Composable
fun FavoritesScreen() {
    val session = AppState.session ?: return
    val coordinator = LocalCoordinator.current
    val user = session.userData
    @Suppress("UNUSED_VARIABLE") val rev = user.revision

    val channels = user.favorites(MediaRef.Kind.live)
    val movies = user.favorites(MediaRef.Kind.movie)
    val series = user.seriesFavorites
    fun removeMenu(ref: MediaRef) = listOf(MenuAction("Remove from Favorites", danger = true) { user.toggleFavorite(ref) })

    if (channels.isEmpty() && movies.isEmpty() && series.isEmpty()) {
        EmptyStateView(Icons.Default.Star, "No favorites yet", "Tap the star on any channel, movie, or series to save it here.")
        return
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top = 8.dp)) {
        if (channels.isNotEmpty()) Rail("Favorite Channels", channels, key = { it.key }) { ref ->
            PosterCard(ref.title, null, ref.poster, Icons.Default.Tv, aspect = 1f, menu = removeMenu(ref)) { coordinator.play(ref) }
        }
        if (movies.isNotEmpty()) Rail("Favorite Movies", movies, key = { it.key }) { ref ->
            PosterCard(ref.title, null, ref.poster, Icons.Default.Movie, menu = removeMenu(ref)) { openFavorite(coordinator, ref) }
        }
        if (series.isNotEmpty()) Rail("Favorite Series", series, key = { it.key }) { ref ->
            PosterCard(ref.title, null, ref.poster, Icons.Default.VideoLibrary, menu = removeMenu(ref)) { openFavorite(coordinator, ref) }
        }
        Text("Tip: long-press an item to remove it.", color = Theme.textTertiary, fontSize = 12.sp,
            modifier = Modifier.padding(16.dp))
    }
}

// MARK: - Recently watched

/**
 * Recently Watched: resume rail, recent channels, and full history. Each item
 * has a long-press "Remove from History"; a button clears everything.
 */
@Composable
fun RecentScreen() {
    val session = AppState.session ?: return
    val coordinator = LocalCoordinator.current
    val user = session.userData
    @Suppress("UNUSED_VARIABLE") val rev = user.revision
    var confirmClear by remember { mutableStateOf(false) }

    val resume = user.continueWatching()
    val byID = remember(session.allLive) { session.allLive.associateBy { it.streamID } }
    val recentChannels = user.recentChannelIDs.mapNotNull { byID[it] }.take(16)
    val vodHistory = user.history.filter { it.ref.isResumable }.take(24)

    fun menu(ref: MediaRef) = listOf(
        MenuAction("Play") { coordinator.play(ref) },
        MenuAction("Remove from History", danger = true) { user.removeHistory(ref) },
    )

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Recently Watched", color = Theme.textPrimary, fontSize = 22.sp, fontWeight = FontWeight.Bold,
                modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
            PillButton("Clear History", filled = false) { confirmClear = true }
        }
        if (resume.isEmpty() && recentChannels.isEmpty() && vodHistory.isEmpty()) {
            EmptyStateView(Icons.Default.Schedule, "Nothing watched yet",
                "Channels and titles you play will show up here so you can pick up where you left off. Long-press any item to remove it.",
                Modifier.fillMaxWidth().padding(top = 40.dp))
        }
        if (resume.isNotEmpty()) Rail("Continue Watching", resume, key = { it.ref.key }) { e ->
            PosterCard(e.ref.title, "Resume", e.ref.poster, Icons.Default.Movie, progress = e.progressFraction,
                menu = menu(e.ref)) { coordinator.play(e.ref) }
        }
        if (recentChannels.isNotEmpty()) Rail("Recent Channels", recentChannels, key = { it.streamID }) { ch ->
            val ref = MediaRef.live(ch)
            PosterCard(ch.name, null, ch.icon, Icons.Default.Tv, aspect = 1f, menu = menu(ref)) { coordinator.play(ref) }
        }
        if (vodHistory.isNotEmpty()) Rail("History", vodHistory, key = { it.ref.key }) { e ->
            PosterCard(e.ref.title, if (e.isFinished) "Watched" else null, e.ref.poster, Icons.Default.Movie,
                progress = if (e.isFinished) null else e.progressFraction, menu = menu(e.ref)) { coordinator.play(e.ref) }
        }
    }

    if (confirmClear) {
        AlertDialog(
            onDismissRequest = { confirmClear = false },
            containerColor = Theme.surface,
            title = { Text("Clear watch history?", color = Theme.textPrimary) },
            text = { Text("This removes resume points and recent channels for this profile. Favorites and settings are not affected.",
                color = Theme.textSecondary) },
            confirmButton = { TextButton(onClick = { user.clearHistory(); confirmClear = false }) { Text("Clear", color = Theme.negative) } },
            dismissButton = { TextButton(onClick = { confirmClear = false }) { Text("Cancel", color = Theme.accent) } },
        )
    }
}

// MARK: - Settings

/** Account info, playback details, storage controls, and about. */
@OptIn(ExperimentalLayoutApi::class, coil.annotation.ExperimentalCoilApi::class)
@Composable
fun SettingsScreen() {
    val session = AppState.session ?: return
    val context = LocalContext.current
    val user = session.auth.userInfo
    var cleared by remember { mutableStateOf<String?>(null) }

    val account = buildList {
        add("Profile" to session.profile.name)
        add("Server" to session.profile.host)
        add("Username" to session.profile.username)
        user?.status?.let { add("Status" to it) }
        val exp = user?.expDateSecs?.takeIf { it > 0 }
        if (exp != null) {
            val days = ((exp * 1000 - System.currentTimeMillis()) / 86_400_000L).coerceAtLeast(0)
            add("Expires" to "${DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(exp * 1000))}  ($days days)")
        } else add("Expires" to "Unlimited / not provided")
        if (user?.activeConnections != null && user.maxConnections != null)
            add("Connections" to "${user.activeConnections} / ${user.maxConnections} active")
        user?.allowedOutputFormats?.takeIf { it.isNotEmpty() }?.let { add("Output Formats" to it.joinToString(", ")) }
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        InfoCard("Account", account)
        InfoCard("Playback", listOf("Live Stream Format" to session.profile.liveFormat.uppercase(),
            "Playback Engine" to "libVLC ${VlcPlayer.version}"))
        Card("Storage") {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                PillButton("Clear Image Cache", filled = false) {
                    context.imageLoader.diskCache?.clear(); context.imageLoader.memoryCache?.clear()
                    cleared = "Image cache cleared."
                }
                PillButton("Clear Content Cache", filled = false) { session.clearCaches(); cleared = "Content cache cleared." }
            }
            cleared?.let { Text(it, color = Theme.positive, fontSize = 12.5.sp) }
        }
        InfoCard("About", listOf("Application" to "IPTVXtremePlayer 1.1", "Platform" to "Android ${android.os.Build.VERSION.RELEASE}"))
        PillButton("Disconnect & Manage Profiles", filled = false) { AppState.disconnect() }
    }
}

@Composable
private fun InfoCard(title: String, rows: List<Pair<String, String>>) {
    Card(title) {
        rows.forEach { (k, v) ->
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(k, color = Theme.textTertiary, fontSize = 13.sp, fontWeight = FontWeight.Medium, modifier = Modifier.width(130.dp))
                Text(v, color = Theme.textPrimary, fontSize = 13.5.sp, fontWeight = FontWeight.Medium, maxLines = 2,
                    overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

// MARK: - Search

/** Global search across channels, movies, and series, shown as rails. */
@Composable
fun SearchScreen(initialQuery: String) {
    val session = AppState.session ?: return
    val coordinator = LocalCoordinator.current
    var query by remember(initialQuery) { mutableStateOf(initialQuery) }
    var field by remember(initialQuery) { mutableStateOf(initialQuery) }
    var ready by remember { mutableStateOf(session.allLive.isNotEmpty() || session.allMovies.isNotEmpty() || session.allSeries.isNotEmpty()) }

    LaunchedEffect(Unit) {
        if (!ready) {
            coroutineScope {
                val a = async { runCatching { session.loadAllLive() } }
                val b = async { runCatching { session.loadAllMovies() } }
                val c = async { runCatching { session.loadAllSeries() } }
                a.await(); b.await(); c.await()
            }
            ready = true
        }
    }

    Column(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Results for “$query”", color = Theme.textPrimary, fontSize = 20.sp, fontWeight = FontWeight.Bold,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
            SearchBox(field, { field = it }, "Search…", Modifier.fillMaxWidth()) {
                if (field.isNotBlank()) query = field.trim()
            }
        }
        if (!ready) { LoadingView("Preparing search…"); return@Column }
        val results = remember(query, session.allLive, session.allMovies, session.allSeries) { session.search(query) }
        if (results.isEmpty) {
            EmptyStateView(Icons.Default.Search, "No matches", "No channels, movies, or series match “$query”.")
            return@Column
        }
        Box(Modifier.weight(1f)) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                if (results.live.isNotEmpty()) Rail("Channels", results.live, key = { it.streamID }) { ch ->
                    PosterCard(ch.name, null, ch.icon, Icons.Default.Tv, aspect = 1f) { coordinator.play(MediaRef.live(ch)) }
                }
                if (results.movies.isNotEmpty()) Rail("Movies", results.movies, key = { it.streamID }) { m ->
                    PosterCard(m.name, null, m.icon, Icons.Default.Movie) { coordinator.openMovie(m) }
                }
                if (results.series.isNotEmpty()) Rail("Series", results.series, key = { it.seriesID }) { s ->
                    PosterCard(s.name, null, s.cover, Icons.Default.VideoLibrary) { coordinator.openSeries(s) }
                }
            }
        }
    }
}
