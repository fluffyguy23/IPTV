package com.iptvxtreme.player.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.iptvxtreme.player.core.AppState
import com.iptvxtreme.player.core.Episode
import com.iptvxtreme.player.core.MediaRef
import com.iptvxtreme.player.core.SeriesInfo
import com.iptvxtreme.player.core.SeriesStream
import com.iptvxtreme.player.core.VODInfo
import com.iptvxtreme.player.core.VODStream
import com.iptvxtreme.player.player.EpisodeNavigator
import com.iptvxtreme.player.player.makeMovieItem
import com.iptvxtreme.player.ui.LocalCoordinator
import com.iptvxtreme.player.ui.Theme
import com.iptvxtreme.player.ui.components.Artwork
import com.iptvxtreme.player.ui.components.LoadingView
import com.iptvxtreme.player.ui.components.PillButton
import com.iptvxtreme.player.ui.components.Selector
import com.iptvxtreme.player.ui.components.formatDuration

/** Poster beside the info column; the poster shrinks on phones. */
@Composable
private fun DetailHeader(poster: String?, placeholder: androidx.compose.ui.graphics.vector.ImageVector,
                         info: @Composable (posterWidth: Dp) -> Unit) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val posterWidth = if (maxWidth >= 600.dp) 230.dp else 120.dp
        Row(horizontalArrangement = Arrangement.spacedBy(if (maxWidth >= 600.dp) 26.dp else 16.dp)) {
            Artwork(poster, placeholder, Modifier.width(posterWidth).aspectRatio(2f / 3f))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(12.dp)) { info(posterWidth) }
        }
    }
}

@Composable
private fun FavToggle(isFav: Boolean, label: String? = null, onToggle: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable(onClick = onToggle)) {
        IconButton(onClick = onToggle) {
            Icon(if (isFav) Icons.Default.Star else Icons.Default.StarBorder, "Favorite",
                tint = if (isFav) Theme.accent else Theme.textSecondary)
        }
        if (label != null) Text(if (isFav) "In Favorites" else label, color = Theme.textSecondary, fontSize = 13.sp,
            fontWeight = FontWeight.Medium, modifier = Modifier.padding(end = 10.dp))
    }
}

@Composable
private fun KeyValue(key: String, value: String) {
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(key, color = Theme.textTertiary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        Text(value, color = Theme.textSecondary, fontSize = 14.sp)
    }
}

// MARK: - Movie detail

/** Movie detail: artwork, metadata, plot, and play / resume / favorite actions. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun VODDetailScreen(movie: VODStream) {
    val session = AppState.session ?: return
    val coordinator = LocalCoordinator.current
    var info by remember { mutableStateOf<VODInfo?>(null) }
    var loaded by remember { mutableStateOf(false) }

    LaunchedEffect(movie.streamID) {
        info = runCatching { session.vodInfo(movie.streamID) }.getOrNull()
        loaded = true
    }
    if (!loaded) { LoadingView(); return }

    @Suppress("UNUSED_VARIABLE") val rev = session.userData.revision
    val ref = MediaRef.movie(movie)
    val resume = session.userData.resumePosition(ref)
    val isFav = session.userData.isFavorite(ref)

    fun play(fromResume: Boolean) {
        val item = session.makeMovieItem(movie, info?.containerExtension)
        coordinator.playInPlayer(if (fromResume) item else item.copy(resumeSecs = 0.0))
    }

    val meta = buildList {
        info?.releaseDate?.takeIf { it.length >= 4 }?.let { add(it.take(4)) }
        info?.genre?.let { add(it) }
        info?.durationSecs?.takeIf { it > 0 }?.let { add(formatDuration(it)) }
        val r = info?.rating?.takeIf { it.isNotEmpty() && it != "0" }
        if (r != null) add("★ $r") else movie.rating5?.takeIf { it > 0 }?.let { add("★ %.1f".format(it)) }
    }.joinToString("  ·  ")

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp)) {
        DetailHeader(info?.posterPath ?: movie.icon, Icons.Default.Movie) {
            Text(info?.name ?: movie.name, color = Theme.textPrimary, fontSize = 24.sp, fontWeight = FontWeight.Bold, maxLines = 3,
                overflow = TextOverflow.Ellipsis)
            if (meta.isNotEmpty()) Text(meta, color = Theme.accent, fontSize = 13.sp, fontWeight = FontWeight.Medium)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                PillButton(if (resume > 10) "Resume" else "Play") { play(resume > 10) }
                if (resume > 10) PillButton("Play from Start", filled = false) { play(false) }
                FavToggle(isFav) { session.userData.toggleFavorite(ref) }
            }
        }
        info?.plot?.let {
            Text("Overview", color = Theme.textPrimary, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            Text(it, color = Theme.textSecondary, fontSize = 14.sp, modifier = Modifier.widthIn(max = 760.dp))
        }
        info?.cast?.let { KeyValue("Cast", it) }
        info?.director?.let { KeyValue("Director", it) }
    }
}

// MARK: - Series detail

/**
 * Series detail: artwork, metadata, season picker, and an episode list with
 * per-episode playback and automatic next-episode advancement.
 */
@Composable
fun SeriesDetailScreen(series: SeriesStream) {
    val session = AppState.session ?: return
    val coordinator = LocalCoordinator.current
    var info by remember { mutableStateOf<SeriesInfo?>(null) }
    var loaded by remember { mutableStateOf(false) }
    var season by remember { mutableLongStateOf(0L) }

    LaunchedEffect(series.seriesID) {
        info = runCatching { session.seriesInfo(series.seriesID) }.getOrNull()
        season = info?.sortedSeasons?.firstOrNull() ?: 0L
        loaded = true
    }
    if (!loaded) { LoadingView(); return }

    @Suppress("UNUSED_VARIABLE") val rev = session.userData.revision
    val favRef = MediaRef.series(series)
    val isFav = session.userData.isFavorite(favRef)
    val seasons = info?.sortedSeasons.orEmpty()

    val meta = buildList {
        (info?.releaseDate ?: series.releaseDate)?.takeIf { it.length >= 4 }?.let { add(it.take(4)) }
        (info?.genre ?: series.genre)?.let { add(it) }
        if (seasons.isNotEmpty()) add("${seasons.size} season${if (seasons.size == 1) "" else "s"}")
        val r = info?.rating?.takeIf { it.isNotEmpty() && it != "0" }
        if (r != null) add("★ $r") else series.rating5?.takeIf { it > 0 }?.let { add("★ %.1f".format(it)) }
    }.joinToString("  ·  ")

    fun playEpisode(ep: Episode) {
        val i = info ?: return
        // Navigator spans the whole series (all seasons) in order, so Prev/Next
        // and auto-advance cross season boundaries.
        val navigator = EpisodeNavigator.forSeries(series, i, ep, session)
        val item = navigator.currentItem() ?: return
        coordinator.playInPlayer(item, navigator)
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp)) {
        DetailHeader(info?.cover ?: series.cover, Icons.Default.VideoLibrary) {
            Text(series.name, color = Theme.textPrimary, fontSize = 24.sp, fontWeight = FontWeight.Bold, maxLines = 3,
                overflow = TextOverflow.Ellipsis)
            if (meta.isNotEmpty()) Text(meta, color = Theme.accent, fontSize = 13.sp, fontWeight = FontWeight.Medium)
            FavToggle(isFav, "Add to Favorites") { session.userData.toggleFavorite(favRef) }
        }
        (info?.plot ?: series.plot)?.let {
            Text(it, color = Theme.textSecondary, fontSize = 14.sp, modifier = Modifier.widthIn(max = 760.dp))
        }

        if (seasons.isEmpty()) {
            Text("No episodes are available for this series.", color = Theme.textTertiary, fontSize = 14.sp)
            return@Column
        }

        Row(verticalAlignment = Alignment.Bottom) {
            Text("Episodes", color = Theme.textPrimary, fontSize = 18.sp, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f))
            Selector(null, seasons.map { "Season $it" }, seasons.indexOf(season).coerceAtLeast(0),
                { season = seasons[it] }, Modifier.width(160.dp))
        }

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            info?.episodesBySeason?.get(season).orEmpty().forEach { ep ->
                val ref = MediaRef.episode(ep, series)
                val pos = session.userData.resumePosition(ref)
                EpisodeRow(ep, progress = ep.durationSecs?.takeIf { it > 0 && pos > 10 }?.let { (pos / it).toFloat() }) {
                    playEpisode(ep)
                }
            }
        }
    }
}

@Composable
private fun EpisodeRow(ep: Episode, progress: Float?, onPlay: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(Theme.surface).clickable(onClick = onPlay)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("${ep.episodeNum}", color = Theme.accent, fontSize = 15.sp, fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center, modifier = Modifier.width(34.dp))
        Column(Modifier.weight(1f)) {
            Text(ep.title.ifEmpty { "Episode ${ep.episodeNum}" }, color = Theme.textPrimary, fontSize = 14.sp,
                fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            ep.durationSecs?.takeIf { it > 0 }?.let {
                Text(formatDuration(it), color = Theme.textTertiary, fontSize = 11.5.sp)
            }
            if (progress != null && progress > 0.01f) {
                Spacer(Modifier.height(4.dp))
                Box(Modifier.fillMaxWidth(0.6f).height(3.dp).background(Theme.border, RoundedCornerShape(2.dp))) {
                    Box(Modifier.fillMaxWidth(progress.coerceIn(0f, 1f)).height(3.dp).background(Theme.accent, RoundedCornerShape(2.dp)))
                }
            }
        }
        Icon(Icons.Default.PlayCircle, "Play", tint = Theme.accent, modifier = Modifier.size(30.dp))
    }
}
