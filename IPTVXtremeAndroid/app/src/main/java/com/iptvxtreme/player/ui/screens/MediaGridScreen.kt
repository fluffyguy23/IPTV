package com.iptvxtreme.player.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.iptvxtreme.player.core.AppState
import com.iptvxtreme.player.core.Category
import com.iptvxtreme.player.core.SeriesStream
import com.iptvxtreme.player.core.VODStream
import com.iptvxtreme.player.core.userMessage
import com.iptvxtreme.player.ui.LocalCoordinator
import com.iptvxtreme.player.ui.components.EmptyStateView
import com.iptvxtreme.player.ui.components.LoadingView
import com.iptvxtreme.player.ui.components.PosterCard
import com.iptvxtreme.player.ui.components.SearchBox
import com.iptvxtreme.player.ui.components.Selector
import com.iptvxtreme.player.ui.Theme

/**
 * Reusable poster grid for Movies and Series, with category filtering,
 * in-section search, and sorting. Fetches per-category to keep payloads small.
 */
@Composable
fun MediaGridScreen(movies: Boolean) {
    val session = AppState.session ?: return
    val coordinator = LocalCoordinator.current

    var categories by remember { mutableStateOf<List<Category>>(emptyList()) }
    var catIndex by remember { mutableIntStateOf(0) }    // 0 = All
    var sort by remember { mutableIntStateOf(0) }        // Default, A–Z, Recently Added, Top Rated
    var filter by remember { mutableStateOf("") }
    var rawMovies by remember { mutableStateOf<List<VODStream>>(emptyList()) }
    var rawSeries by remember { mutableStateOf<List<SeriesStream>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var loadError by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(coordinator.refreshTick) {
        val force = coordinator.refreshTick > 0
        categories = runCatching { if (movies) session.movieCategories(force) else session.seriesCategories(force) }
            .getOrDefault(categories)
    }

    LaunchedEffect(catIndex, categories, coordinator.refreshTick) {
        loading = true; loadError = null
        val force = coordinator.refreshTick > 0
        val catID = categories.getOrNull(catIndex - 1)?.id
        try {
            if (movies) rawMovies = if (catID == null) session.loadAllMovies(force) else session.client.vodStreams(catID)
            else rawSeries = if (catID == null) session.loadAllSeries(force) else session.client.series(catID)
        } catch (e: Exception) {
            loadError = e.userMessage()
        }
        loading = false
    }

    val q = filter.trim().lowercase()
    val movieList = remember(rawMovies, q, sort) {
        var l = if (q.isEmpty()) rawMovies else rawMovies.filter { it.name.lowercase().contains(q) }
        l = when (sort) {
            1 -> l.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })
            2 -> l.sortedByDescending { it.addedTimestamp ?: 0 }
            3 -> l.sortedByDescending { it.rating5 ?: 0.0 }
            else -> l
        }
        l
    }
    val seriesList = remember(rawSeries, q, sort) {
        var l = if (q.isEmpty()) rawSeries else rawSeries.filter { it.name.lowercase().contains(q) }
        l = when (sort) {
            1 -> l.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })
            2 -> l.sortedByDescending { it.lastModified ?: 0 }
            3 -> l.sortedByDescending { it.rating5 ?: 0.0 }
            else -> l
        }
        l
    }

    Column(Modifier.fillMaxSize()) {
        // Toolbar: category, sort, filter — one row on wide screens, stacked on phones.
        BoxWithConstraints(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)) {
            val cats = listOf("All") + categories.map { it.name }
            val sorts = listOf("Default", "A–Z", "Recently Added", "Top Rated")
            val placeholder = "Filter ${if (movies) "movies" else "series"}…"
            if (maxWidth >= 720.dp) {
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.Bottom) {
                    Selector("Category", cats, catIndex, { catIndex = it }, Modifier.width(240.dp))
                    Selector("Sort", sorts, sort, { sort = it }, Modifier.width(170.dp))
                    Box(Modifier.weight(1f))
                    SearchBox(filter, { filter = it }, placeholder, Modifier.width(260.dp))
                }
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Selector("Category", cats, catIndex, { catIndex = it }, Modifier.weight(1.4f))
                        Selector("Sort", sorts, sort, { sort = it }, Modifier.weight(1f))
                    }
                    SearchBox(filter, { filter = it }, placeholder, Modifier.fillMaxWidth())
                }
            }
        }

        Box(Modifier.weight(1f)) {
            val count = if (movies) movieList.size else seriesList.size
            when {
                loading -> LoadingView()
                loadError != null -> EmptyStateView(Icons.Default.WifiOff, "Couldn't load", loadError ?: "Please try again.",
                    actionTitle = "Retry") { coordinator.refresh() }
                count == 0 -> EmptyStateView(Icons.Default.Search, "No results", "Nothing matches the current filter.")
                else -> {
                    val gridState = rememberLazyGridState()
                    LazyVerticalGrid(
                        columns = GridCells.Adaptive(minSize = Theme.posterWidth - 14.dp),
                        state = gridState,
                        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 24.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalArrangement = Arrangement.spacedBy(18.dp),
                    ) {
                        if (movies) items(movieList, key = { it.streamID }) { m ->
                            PosterCard(m.name, null, m.icon, Icons.Default.Movie, width = null,
                                badge = m.rating5?.takeIf { it > 0 }?.let { "%.1f".format(it) }) { coordinator.openMovie(m) }
                        } else items(seriesList, key = { it.seriesID }) { s ->
                            PosterCard(s.name, null, s.cover, Icons.Default.VideoLibrary, width = null,
                                badge = s.rating5?.takeIf { it > 0 }?.let { "%.1f".format(it) }) { coordinator.openSeries(s) }
                        }
                    }
                }
            }
        }
    }
}
