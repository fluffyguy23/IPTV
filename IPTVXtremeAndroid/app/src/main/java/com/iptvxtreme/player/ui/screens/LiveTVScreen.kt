package com.iptvxtreme.player.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.iptvxtreme.player.core.AppState
import com.iptvxtreme.player.core.Category
import com.iptvxtreme.player.core.LiveStream
import com.iptvxtreme.player.core.MediaRef
import com.iptvxtreme.player.core.userMessage
import com.iptvxtreme.player.player.PlayerSurface
import com.iptvxtreme.player.player.makeLiveItem
import com.iptvxtreme.player.ui.LocalCoordinator
import com.iptvxtreme.player.ui.Theme
import com.iptvxtreme.player.ui.components.Artwork
import com.iptvxtreme.player.ui.components.EmptyStateView
import com.iptvxtreme.player.ui.components.LoadingView
import com.iptvxtreme.player.ui.components.SearchBox
import com.iptvxtreme.player.ui.components.Selector
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Live TV: category + channel list, embedded player and EPG now/next.
 * Wide screens keep the macOS split (list left, player right); phones stack the
 * player above the list. Fast channel switching reuses one player instance.
 */
@Composable
fun LiveTVScreen() {
    val session = AppState.session ?: return
    val coordinator = LocalCoordinator.current

    var categories by remember { mutableStateOf<List<Category>>(emptyList()) }
    var selectedIndex by remember { mutableIntStateOf(0) }   // 0 = All, 1 = Favorites, 2.. = categories
    var channels by remember { mutableStateOf<List<LiveStream>>(emptyList()) }
    var filter by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(true) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var current by remember { mutableStateOf<LiveStream?>(null) }
    var epgNow by remember { mutableStateOf("") }
    var epgNext by remember { mutableStateOf("") }
    // The embedded player is removed while the full-screen player owns the
    // (often single) provider connection, and comes back on return.
    var suspended by remember { mutableStateOf(false) }

    LaunchedEffect(coordinator.refreshTick) {
        categories = runCatching { session.liveCategories(coordinator.refreshTick > 0) }.getOrDefault(categories)
    }

    LaunchedEffect(selectedIndex, coordinator.refreshTick, categories) {
        loading = true; loadError = null
        val force = coordinator.refreshTick > 0
        try {
            channels = when {
                selectedIndex == 1 -> {
                    val all = runCatching { session.loadAllLive() }.getOrDefault(session.allLive)
                    val favIDs = session.userData.favorites(MediaRef.Kind.live).mapNotNull { it.streamID }.toSet()
                    all.filter { it.streamID in favIDs }
                }
                selectedIndex >= 2 && selectedIndex - 2 < categories.size ->
                    session.client.liveStreams(categories[selectedIndex - 2].id)
                else -> session.loadAllLive(force)
            }
        } catch (e: Exception) {
            loadError = e.userMessage()
            channels = emptyList()
        }
        loading = false
    }

    LaunchedEffect(current?.streamID) {
        val ch = current ?: return@LaunchedEffect
        epgNow = ""; epgNext = ""
        val listings = runCatching { session.client.shortEPG(ch.streamID, 2) }.getOrDefault(emptyList())
        val df = SimpleDateFormat("HH:mm", Locale.getDefault())
        fun line(prefix: String, start: Long?, title: String) =
            "$prefix: ${start?.let { df.format(Date(it * 1000)) + "  " } ?: ""}$title"
        epgNow = listings.firstOrNull()?.let { line("Now", it.startSecs, it.title) } ?: "No programme guide available"
        epgNext = listings.getOrNull(1)?.let { line("Next", it.startSecs, it.title) } ?: ""
    }

    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val obs = LifecycleEventObserver { _, e -> if (e == Lifecycle.Event.ON_RESUME) suspended = false }
        lifecycleOwner.lifecycle.addObserver(obs)
        onDispose { lifecycleOwner.lifecycle.removeObserver(obs) }
    }

    val filtered = remember(channels, filter) {
        val q = filter.trim().lowercase()
        if (q.isEmpty()) channels else channels.filter { it.name.lowercase().contains(q) }
    }
    @Suppress("UNUSED_VARIABLE") val rev = session.userData.revision
    val isFav = current?.let { session.userData.isFavorite(MediaRef.live(it)) } == true

    val playerPane: @Composable (Modifier) -> Unit = { mod ->
        Column(mod) {
            // 16:9, shrinking to the available height on short landscape screens.
            Box(Modifier.align(Alignment.CenterHorizontally).weight(1f, fill = false).aspectRatio(16f / 9f).background(Color.Black)) {
                val ch = current
                if (ch == null || suspended) {
                    EmptyStateView(Icons.Default.Tv, if (ch == null) "Select a channel" else ch.name,
                        if (ch == null) "Choose a channel from the list to start watching." else "Playing full screen…")
                } else {
                    val item = remember(ch.streamID) { session.makeLiveItem(ch) }
                    PlayerSurface(
                        session = session, item = item, embedded = true, modifier = Modifier.fillMaxSize(),
                        onFullscreen = {
                            suspended = true
                            coordinator.playInPlayer(session.makeLiveItem(ch))
                        },
                    )
                }
            }
            // Info bar: channel name, EPG now/next, favorite toggle
            Row(Modifier.fillMaxWidth().background(Theme.surface).padding(start = 16.dp, end = 8.dp, top = 10.dp, bottom = 10.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(current?.name ?: "No channel selected", color = Theme.textPrimary, fontSize = 16.sp,
                        fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (epgNow.isNotEmpty()) Text(epgNow, color = Theme.accent, fontSize = 13.sp, fontWeight = FontWeight.Medium,
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (epgNext.isNotEmpty()) Text(epgNext, color = Theme.textTertiary, fontSize = 12.sp, maxLines = 1,
                        overflow = TextOverflow.Ellipsis)
                }
                if (current != null) {
                    IconButton(onClick = { current?.let { session.userData.toggleFavorite(MediaRef.live(it)) } }) {
                        Icon(if (isFav) Icons.Default.Star else Icons.Default.StarBorder, "Favorite",
                            tint = if (isFav) Theme.accent else Theme.textSecondary)
                    }
                }
            }
        }
    }

    val listPane: @Composable (Modifier) -> Unit = { mod ->
        Column(mod.background(Theme.sidebar).padding(top = 12.dp)) {
            Selector(null, listOf("All Channels", "★ Favorites") + categories.map { it.name }, selectedIndex,
                { selectedIndex = it }, Modifier.padding(horizontal = 12.dp).fillMaxWidth())
            Spacer(Modifier.height(10.dp))
            SearchBox(filter, { filter = it }, "Search channels…", Modifier.padding(horizontal = 12.dp).fillMaxWidth())
            Spacer(Modifier.height(8.dp))
            Box(Modifier.weight(1f)) {
                when {
                    loading -> LoadingView()
                    loadError != null -> EmptyStateView(Icons.Default.WifiOff, "Couldn't load", loadError ?: "")
                    filtered.isEmpty() -> EmptyStateView(Icons.Default.Tv, "No channels",
                        if (selectedIndex == 1) "Tap the star on a channel to add it to your favorites." else "Nothing matches the current filter.")
                    else -> {
                        val listState = rememberLazyListState()
                        LazyColumn(state = listState, contentPadding = PaddingValues(6.dp)) {
                            items(filtered, key = { it.streamID }) { ch ->
                                ChannelRow(ch, selected = ch.streamID == current?.streamID) { current = ch; suspended = false }
                            }
                        }
                    }
                }
            }
        }
    }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        if (maxWidth >= 720.dp) {
            Row(Modifier.fillMaxSize()) {
                listPane(Modifier.width(330.dp).fillMaxHeight())
                playerPane(Modifier.weight(1f).fillMaxHeight().background(Theme.background))
            }
        } else {
            Column(Modifier.fillMaxSize()) {
                playerPane(Modifier.fillMaxWidth())
                listPane(Modifier.fillMaxWidth().weight(1f))
            }
        }
    }
}

/** Channel row: logo, name, and channel number. */
@Composable
private fun ChannelRow(ch: LiveStream, selected: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(vertical = 2.dp).clip(RoundedCornerShape(8.dp))
            .background(if (selected) Theme.accentSoft else Color.Transparent)
            .clickable(onClick = onClick).padding(horizontal = 8.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Artwork(ch.icon, Icons.Default.Tv, Modifier.size(42.dp), corner = 6.dp,
            contentScale = androidx.compose.ui.layout.ContentScale.Fit)
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(ch.name, color = if (selected) Theme.accent else Theme.textPrimary, fontSize = 14.sp,
                fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            ch.num?.let { Text("CH $it", color = Theme.textTertiary, fontSize = 11.sp) }
        }
    }
}
