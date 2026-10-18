package com.iptvxtreme.player.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDrawerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.iptvxtreme.player.core.AppState
import com.iptvxtreme.player.core.ProfileStore
import com.iptvxtreme.player.core.Session
import com.iptvxtreme.player.core.userMessage
import com.iptvxtreme.player.player.EpisodeNavigator
import com.iptvxtreme.player.player.PlaybackItem
import com.iptvxtreme.player.ui.components.LoadingView
import com.iptvxtreme.player.ui.components.SearchBox
import com.iptvxtreme.player.ui.screens.ConnectionScreen
import com.iptvxtreme.player.ui.screens.FavoritesScreen
import com.iptvxtreme.player.ui.screens.HomeScreen
import com.iptvxtreme.player.ui.screens.LiveTVScreen
import com.iptvxtreme.player.ui.screens.MediaGridScreen
import com.iptvxtreme.player.ui.screens.RecentScreen
import com.iptvxtreme.player.ui.screens.SearchScreen
import com.iptvxtreme.player.ui.screens.SeriesDetailScreen
import com.iptvxtreme.player.ui.screens.SettingsScreen
import com.iptvxtreme.player.ui.screens.VODDetailScreen
import kotlinx.coroutines.launch

/** Swaps between the connection screen and the library; auto-connects on cold start. */
@Composable
fun AppRoot(launchPlayer: (PlaybackItem, EpisodeNavigator?) -> Unit) {
    val session = AppState.session
    var connecting by remember { mutableStateOf<String?>(null) }
    var connectError by remember { mutableStateOf<String?>(null) }

    // Seamless relaunch: reconnect to the last profile with its stored password.
    LaunchedEffect(Unit) {
        if (AppState.session == null && !AppState.autoConnectTried) {
            AppState.autoConnectTried = true
            val last = ProfileStore.lastUsedProfile ?: return@LaunchedEffect
            connecting = last.name
            try {
                AppState.connect(last)
            } catch (e: Exception) {
                connectError = "Couldn't reconnect to ${last.name}: ${e.userMessage()}"
            }
            connecting = null
        }
    }

    Box(Modifier.fillMaxSize().background(Theme.background)) {
        when {
            session != null -> key(session) { LibraryShell(session, launchPlayer) }
            connecting != null -> LoadingView("Connecting to $connecting…",
                Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars))
            else -> ConnectionScreen(initialError = connectError)
        }
    }
}

/**
 * The library shell: sidebar + top bar + content on wide screens (tablets, TV,
 * landscape), and a drawer + top bar + bottom navigation on phones.
 */
@Composable
private fun LibraryShell(session: Session, launchPlayer: (PlaybackItem, EpisodeNavigator?) -> Unit) {
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var confirmDisconnect by remember { mutableStateOf(false) }
    val coordinator = remember(session) { AppCoordinator(launchPlayer) { errorMessage = it } }
    val drawerState = rememberDrawerState(DrawerValue.Closed)
    val scope = rememberCoroutineScope()

    BackHandler(enabled = drawerState.isOpen || coordinator.canPop || coordinator.section != Section.Home) {
        when {
            drawerState.isOpen -> scope.launch { drawerState.close() }
            coordinator.pop() -> {}
            else -> coordinator.selectSection(Section.Home)
        }
    }

    CompositionLocalProvider(LocalCoordinator provides coordinator) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val wide = maxWidth >= 840.dp
            val content: @Composable () -> Unit = {
                Box(Modifier.fillMaxSize().background(Theme.background)) {
                    AnimatedContent(coordinator.top, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "nav") { route ->
                        RouteContent(route)
                    }
                }
            }
            if (wide) {
                Row(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.navigationBars.union(WindowInsets.displayCutout))) {
                    Sidebar(coordinator, Modifier.width(Theme.sidebarWidth).fillMaxHeight()
                        .windowInsetsPadding(WindowInsets.statusBars)) { confirmDisconnect = true }
                    Column(Modifier.weight(1f).windowInsetsPadding(WindowInsets.statusBars)) {
                        TopBar(session, coordinator, wide = true, onMenu = null)
                        content()
                    }
                }
            } else {
                ModalNavigationDrawer(
                    drawerState = drawerState,
                    drawerContent = {
                        ModalDrawerSheet(drawerContainerColor = Theme.sidebar, modifier = Modifier.width(260.dp)) {
                            Sidebar(coordinator, Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars),
                                onSelected = { scope.launch { drawerState.close() } }) {
                                scope.launch { drawerState.close() }
                                confirmDisconnect = true
                            }
                        }
                    },
                ) {
                    Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.statusBars.union(WindowInsets.displayCutout))) {
                        TopBar(session, coordinator, wide = false, onMenu = { scope.launch { drawerState.open() } })
                        Box(Modifier.weight(1f)) { content() }
                        BottomNav(coordinator)
                    }
                }
            }
        }

        if (confirmDisconnect) {
            AlertDialog(
                onDismissRequest = { confirmDisconnect = false },
                containerColor = Theme.surface,
                title = { Text("Disconnect from ${session.profile.name}?", color = Theme.textPrimary) },
                text = { Text("You can reconnect any time from the connection screen.", color = Theme.textSecondary) },
                confirmButton = {
                    TextButton(onClick = { confirmDisconnect = false; AppState.disconnect() }) {
                        Text("Disconnect", color = Theme.negative)
                    }
                },
                dismissButton = { TextButton(onClick = { confirmDisconnect = false }) { Text("Cancel", color = Theme.accent) } },
            )
        }
        errorMessage?.let { msg ->
            AlertDialog(
                onDismissRequest = { errorMessage = null },
                containerColor = Theme.surface,
                title = { Text("Playback error", color = Theme.textPrimary) },
                text = { Text(msg, color = Theme.textSecondary) },
                confirmButton = { TextButton(onClick = { errorMessage = null }) { Text("OK", color = Theme.accent) } },
            )
        }
    }
}

@Composable
private fun RouteContent(route: Route) {
    when (route) {
        is Route.Root -> when (route.section) {
            Section.Home -> HomeScreen()
            Section.LiveTV -> LiveTVScreen()
            Section.Movies -> MediaGridScreen(movies = true)
            Section.Series -> MediaGridScreen(movies = false)
            Section.Favorites -> FavoritesScreen()
            Section.Recent -> RecentScreen()
            Section.Settings -> SettingsScreen()
        }
        is Route.MovieDetail -> VODDetailScreen(route.movie)
        is Route.SeriesDetail -> SeriesDetailScreen(route.series)
        is Route.Search -> SearchScreen(route.query)
    }
}

// MARK: - Sidebar

/** Left navigation rail: brand, section rows, and a disconnect button. */
@Composable
private fun Sidebar(coordinator: AppCoordinator, modifier: Modifier, onSelected: () -> Unit = {}, onDisconnect: () -> Unit) {
    val selected = (coordinator.stack.firstOrNull() as? Route.Root)?.section
    Column(modifier.background(Theme.sidebar)) {
        Column(Modifier.padding(start = 20.dp, top = 24.dp, bottom = 22.dp)) {
            Row {
                Text("IPTV", color = Theme.textPrimary, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                Text("Xtreme", color = Theme.accent, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            }
            Text("PLAYER", color = Theme.textTertiary, fontSize = 9.sp, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(start = 1.dp))
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 10.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Section.entries.forEach { s ->
                SidebarRow(s.title, s.icon, isSelected = s == selected) {
                    coordinator.selectSection(s)
                    onSelected()
                }
            }
        }
        Box(Modifier.padding(start = 10.dp, end = 10.dp, bottom = 16.dp)) {
            SidebarRow("Disconnect", Icons.AutoMirrored.Filled.Logout, isSelected = false, danger = true, onClick = onDisconnect)
        }
    }
}

@Composable
private fun SidebarRow(title: String, icon: ImageVector, isSelected: Boolean, danger: Boolean = false, onClick: () -> Unit) {
    val accent = if (danger) Theme.negative else Theme.accent
    Row(
        Modifier.fillMaxWidth().height(44.dp).clip(RoundedCornerShape(8.dp))
            .background(if (isSelected) Theme.accentSoft else Color.Transparent)
            .clickable(onClick = onClick).padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = when {
            isSelected -> accent
            danger -> Theme.negative.copy(alpha = 0.8f)
            else -> Theme.textSecondary
        }, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(12.dp))
        Text(title, fontSize = 14.sp, fontWeight = FontWeight.Medium, color = when {
            isSelected -> Theme.textPrimary
            danger -> Theme.negative.copy(alpha = 0.9f)
            else -> Theme.textSecondary
        })
    }
}

// MARK: - Top bar

/** Top bar: menu/back, section title, global search, profile status, and refresh. */
@Composable
private fun TopBar(session: Session, coordinator: AppCoordinator, wide: Boolean, onMenu: (() -> Unit)?) {
    var query by remember { mutableStateOf("") }
    var searchOpen by remember { mutableStateOf(false) }
    val title = when (val r = coordinator.top) {
        is Route.Root -> r.section.title
        is Route.Search -> "Search"
        else -> ""
    }
    val statusColor = when ((session.auth.userInfo?.status ?: "").lowercase()) {
        "active" -> Theme.positive
        "expired", "banned", "disabled" -> Theme.negative
        else -> Theme.warning
    }
    Column {
        Row(Modifier.fillMaxWidth().height(Theme.topBarHeight).padding(horizontal = if (wide) 20.dp else 4.dp),
            verticalAlignment = Alignment.CenterVertically) {
            when {
                coordinator.canPop -> IconButton(onClick = { coordinator.pop() }) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = Theme.textPrimary)
                }
                onMenu != null -> IconButton(onClick = onMenu) { Icon(Icons.Default.Menu, "Menu", tint = Theme.textPrimary) }
            }
            if (!searchOpen || wide) {
                Text(title, color = Theme.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.SemiBold, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f).padding(start = if (wide && !coordinator.canPop) 4.dp else 0.dp))
            }
            if (wide) {
                SearchBox(query, { query = it }, "Search channels, movies, series…", Modifier.width(300.dp)) {
                    coordinator.performSearch(query)
                }
                Spacer(Modifier.width(14.dp))
                Row(Modifier.clip(RoundedCornerShape(14.dp)).background(Theme.surface).padding(horizontal = 12.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(8.dp).clip(CircleShape).background(statusColor))
                    Spacer(Modifier.width(7.dp))
                    Text(session.profile.name, color = Theme.textSecondary, fontSize = 12.5.sp, fontWeight = FontWeight.Medium,
                        maxLines = 1)
                }
            } else if (searchOpen) {
                SearchBox(query, { query = it }, "Search…", Modifier.weight(1f)) {
                    coordinator.performSearch(query)
                    searchOpen = false
                }
            } else {
                IconButton(onClick = { searchOpen = true }) { Icon(Icons.Default.Search, "Search", tint = Theme.textPrimary) }
                Box(Modifier.size(8.dp).clip(CircleShape).background(statusColor))
            }
            IconButton(onClick = { coordinator.refresh() }) { Icon(Icons.Default.Refresh, "Refresh", tint = Theme.textSecondary) }
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(Theme.border))
    }
}

// MARK: - Bottom navigation (phones)

@Composable
private fun BottomNav(coordinator: AppCoordinator) {
    val selected = (coordinator.stack.firstOrNull() as? Route.Root)?.section
    val items = listOf(Section.Home, Section.LiveTV, Section.Movies, Section.Series, Section.Favorites)
    Column {
        Box(Modifier.fillMaxWidth().height(1.dp).background(Theme.border))
        NavigationBar(containerColor = Theme.sidebar, tonalElevation = 0.dp,
            windowInsets = WindowInsets.navigationBars) {
            items.forEach { s ->
                NavigationBarItem(
                    selected = s == selected,
                    onClick = { coordinator.selectSection(s) },
                    icon = { Icon(s.icon, null) },
                    label = { Text(if (s == Section.LiveTV) "Live" else s.title, fontSize = 11.sp, maxLines = 1) },
                    colors = NavigationBarItemDefaults.colors(
                        selectedIconColor = Theme.accent, selectedTextColor = Theme.textPrimary,
                        unselectedIconColor = Theme.textSecondary, unselectedTextColor = Theme.textSecondary,
                        indicatorColor = Theme.accentSoft,
                    ),
                )
            }
        }
    }
}
