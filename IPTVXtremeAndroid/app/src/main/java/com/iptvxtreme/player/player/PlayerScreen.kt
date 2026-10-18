package com.iptvxtreme.player.player

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Forward10
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay10
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.pointer.pointerInput
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.iptvxtreme.player.core.Session
import com.iptvxtreme.player.ui.Theme
import com.iptvxtreme.player.ui.components.formatHMS
import kotlinx.coroutines.delay
import org.videolan.libvlc.util.VLCVideoLayout

/**
 * Full playback surface with auto-hiding controls. Used both embedded (Live TV)
 * and inside PlayerActivity (movies / series / full-screen live).
 */
@Composable
fun PlayerSurface(
    session: Session,
    item: PlaybackItem,
    embedded: Boolean,
    modifier: Modifier = Modifier,
    navigator: EpisodeNavigator? = null,
    onClose: () -> Unit = {},
    onFullscreen: (() -> Unit)? = null,
    onItemChanged: (PlaybackItem) -> Unit = {},
) {
    val player = remember { VlcPlayer() }
    var current by remember { mutableStateOf(item) }
    var controlsVisible by remember { mutableStateOf(true) }
    var interaction by remember { mutableIntStateOf(0) }   // bump to restart the auto-hide timer
    var scrubbing by remember { mutableStateOf(false) }
    var scrubValue by remember { mutableFloatStateOf(0f) }
    var showSettings by remember { mutableStateOf(false) }
    var aspect by remember { mutableStateOf<String?>(null) }
    var fill by remember { mutableStateOf(false) }
    var episodeTick by remember { mutableIntStateOf(0) }   // recompute Prev/Next enablement
    val focus = remember { FocusRequester() }

    // Mutable per-item playback bookkeeping (not UI state).
    val book = remember { object { var didApplyResume = false; var lastSaved = 0L; var stoppedByLifecycle = false } }

    fun saveProgress(force: Boolean) {
        if (current.isLive) return
        val now = System.currentTimeMillis()
        if (!force && now - book.lastSaved < 5000) return
        book.lastSaved = now
        val pos = player.currentTimeMs / 1000.0
        val dur = player.currentLengthMs / 1000.0
        if (pos > 0) session.userData.updateProgress(current.ref, pos, dur)
    }

    fun start(newItem: PlaybackItem) {
        book.didApplyResume = false
        current = newItem
        player.load(newItem.url, newItem.mediaOptions)
        player.setAspectRatio(aspect)
        player.setFill(fill)
        player.play()
        session.userData.recordPlay(newItem.ref)
        controlsVisible = true
        interaction++
        episodeTick++
        onItemChanged(newItem)
    }

    /** Switch to a new item without tearing down the surface (zapping, next/prev episode). */
    fun replace(newItem: PlaybackItem) {
        saveProgress(force = true)
        player.stop()
        start(newItem)
    }

    val closeState = rememberUpdatedState(onClose)
    player.onEvent = { state ->
        when (state) {
            VlcPlayer.State.Playing -> {
                // libVLC often reports Playing before the length is known; wait for a
                // real length so the one-shot resume isn't wasted.
                if (!book.didApplyResume && player.currentLengthMs > 0) {
                    if (current.resumeSecs > 10) player.seek((current.resumeSecs * 1000).toLong())
                    book.didApplyResume = true
                }
                saveProgress(force = false)
            }
            VlcPlayer.State.Ended -> {
                saveProgress(force = true)
                val next = navigator?.takeIf { it.hasNext }?.next()
                when {
                    next != null -> replace(next)
                    !embedded -> closeState.value()
                }
            }
            else -> {}
        }
    }

    // Initial start, and channel zapping from the embedded Live TV list.
    LaunchedEffect(item.url) {
        if (player.state == VlcPlayer.State.Nothing) start(item) else if (item.url != current.url) replace(item)
    }

    // Stop when the app goes to the background; resume where we were on return.
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_STOP -> {
                    saveProgress(force = true)
                    val pos = player.currentTimeMs / 1000.0
                    if (!current.isLive && pos > 0) current = current.copy(resumeSecs = pos)
                    book.stoppedByLifecycle = true
                    player.stop()
                }
                Lifecycle.Event.ON_START -> if (book.stoppedByLifecycle) {
                    book.stoppedByLifecycle = false
                    start(current)
                }
                else -> {}
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            saveProgress(force = true)
            player.release()
        }
    }

    // Auto-hide controls after 3.5 s of no interaction while playing.
    LaunchedEffect(interaction, controlsVisible, player.state) {
        if (controlsVisible && player.state == VlcPlayer.State.Playing && !scrubbing && !showSettings) {
            delay(3500)
            controlsVisible = false
        }
    }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }

    fun reveal() { controlsVisible = true; interaction++ }
    fun togglePlay() {
        when {
            player.state == VlcPlayer.State.Paused -> player.setPaused(false)
            player.isPlaying -> player.setPaused(true)
            else -> start(current)
        }
        reveal()
    }
    fun seekBy(deltaMs: Long) {
        if (current.isLive || !player.isSeekable) return
        val now = player.currentTimeMs
        val length = player.currentLengthMs
        var target = now + deltaMs
        // Never clamp below the current position (would seek backward in the last second).
        if (deltaMs > 0 && length > 0) target = minOf(target, maxOf(now, length - 1000))
        player.seek(target.coerceAtLeast(0))
        reveal()
    }
    fun goEpisode(next: Boolean) {
        val nav = navigator ?: return
        val newItem = (if (next) nav.next() else nav.previous()) ?: return
        replace(newItem)
    }

    val buffering = player.state == VlcPlayer.State.Opening || player.state == VlcPlayer.State.Buffering

    Box(
        modifier.background(Color.Black)
            .focusRequester(focus).focusable()
            .onKeyEvent { e ->
                if (e.type != KeyEventType.KeyDown) return@onKeyEvent false
                when (e.key) {
                    Key.Spacebar, Key.MediaPlayPause, Key.DirectionCenter, Key.Enter, Key.NumPadEnter ->
                        { if (controlsVisible || e.key == Key.Spacebar || e.key == Key.MediaPlayPause) togglePlay() else reveal(); true }
                    Key.DirectionLeft, Key.MediaRewind -> { seekBy(-10_000); true }
                    Key.DirectionRight, Key.MediaFastForward -> { seekBy(10_000); true }
                    Key.MediaNext -> { goEpisode(true); true }
                    Key.MediaPrevious -> { goEpisode(false); true }
                    Key.M -> { player.toggleMute(); reveal(); true }
                    Key.F -> { onFullscreen?.invoke(); true }
                    Key.DirectionUp, Key.DirectionDown -> { reveal(); false }
                    else -> false
                }
            }
    ) {
        AndroidView(
            factory = { ctx -> VLCVideoLayout(ctx).also { it.keepScreenOn = true; player.attach(it) } },
            modifier = Modifier.fillMaxSize(),
            onRelease = { player.detach() },
        )

        // Gesture layer: tap toggles controls; double-tap left/right half seeks ±10 s.
        Box(Modifier.fillMaxSize().pointerInput(current.isLive) {
            detectTapGestures(
                onTap = { if (controlsVisible) controlsVisible = false else reveal() },
                onDoubleTap = { pos ->
                    if (!current.isLive) seekBy(if (pos.x < size.width / 2) -10_000 else 10_000) else togglePlay()
                },
            )
        })

        if (buffering) {
            CircularProgressIndicator(color = Theme.accent, strokeWidth = 3.dp,
                modifier = Modifier.align(Alignment.Center).size(44.dp))
        }
        if (player.state == VlcPlayer.State.Error) {
            Column(Modifier.align(Alignment.Center).widthIn(max = 420.dp).padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally) {
                Text("This stream could not be played. It may be offline, in an unsupported format, or your connection limit may be reached.",
                    color = Theme.textSecondary, fontSize = 14.sp, textAlign = TextAlign.Center)
                Spacer(Modifier.height(12.dp))
                Text("Retry", color = Theme.accent, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable { start(current) }.padding(10.dp))
            }
        }

        AnimatedVisibility(controlsVisible, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.fillMaxSize()) {
            BoxWithConstraints(Modifier.fillMaxSize()) {
                val compact = maxWidth < 600.dp
                val insets = if (embedded) Modifier else Modifier.windowInsetsPadding(WindowInsets.safeDrawing)

                // Top bar: title + close
                Row(
                    Modifier.align(Alignment.TopCenter).fillMaxWidth()
                        .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.75f), Color.Transparent)))
                        .then(insets).padding(horizontal = 12.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(current.title, color = Theme.textPrimary, fontSize = if (compact) 14.sp else 15.sp,
                        fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f).padding(start = 8.dp))
                    if (!embedded) CtlButton(Icons.Default.Close, "Close") { onClose() }
                }

                // Bottom bar: timeline row + transport row
                Column(
                    Modifier.align(Alignment.BottomCenter).fillMaxWidth()
                        .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.85f))))
                        .then(insets).padding(horizontal = 12.dp, vertical = if (compact) 4.dp else 10.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        val cur = if (scrubbing) scrubValue.toDouble() else player.timeMs / 1000.0
                        Text(formatHMS(cur), color = Theme.textSecondary, fontSize = 12.sp, fontWeight = FontWeight.Medium,
                            modifier = Modifier.padding(horizontal = 6.dp))
                        if (!current.isLive) {
                            val total = (player.lengthMs / 1000f).coerceAtLeast(0f)
                            Slider(
                                value = if (scrubbing) scrubValue else (player.timeMs / 1000f).coerceIn(0f, total.coerceAtLeast(0.001f)),
                                onValueChange = { scrubbing = true; scrubValue = it; reveal() },
                                onValueChangeFinished = { player.seek((scrubValue * 1000).toLong()); scrubbing = false },
                                valueRange = 0f..total.coerceAtLeast(0.001f),
                                enabled = total > 0 && player.isSeekable,
                                colors = SliderDefaults.colors(thumbColor = Theme.accent, activeTrackColor = Theme.accent,
                                    inactiveTrackColor = Color.White.copy(alpha = 0.25f)),
                                modifier = Modifier.weight(1f).height(28.dp),
                            )
                            Text(formatHMS(total.toDouble()), color = Theme.textSecondary, fontSize = 12.sp,
                                fontWeight = FontWeight.Medium, modifier = Modifier.padding(horizontal = 6.dp))
                        } else {
                            Spacer(Modifier.weight(1f))
                            Text("● LIVE", color = Theme.negative, fontSize = 11.sp, fontWeight = FontWeight.Bold,
                                modifier = Modifier.padding(horizontal = 6.dp))
                        }
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                        val hasPrev = remember(episodeTick) { navigator?.hasPrev == true }
                        val hasNext = remember(episodeTick) { navigator?.hasNext == true }
                        if (navigator != null) CtlButton(Icons.Default.SkipPrevious, "Previous episode", enabled = hasPrev) { goEpisode(false) }
                        if (!current.isLive) CtlButton(Icons.Default.Replay10, "Back 10 seconds", enabled = player.isSeekable) { seekBy(-10_000) }
                        CtlButton(if (player.state == VlcPlayer.State.Playing || player.state == VlcPlayer.State.Buffering) Icons.Default.Pause else Icons.Default.PlayArrow,
                            "Play/Pause", big = true) { togglePlay() }
                        if (!current.isLive) CtlButton(Icons.Default.Forward10, "Forward 10 seconds", enabled = player.isSeekable) { seekBy(10_000) }
                        if (navigator != null) CtlButton(Icons.Default.SkipNext, "Next episode", enabled = hasNext) { goEpisode(true) }
                        Spacer(Modifier.weight(1f))
                        CtlButton(if (player.isMuted) Icons.AutoMirrored.Filled.VolumeOff else Icons.AutoMirrored.Filled.VolumeUp, "Mute") {
                            player.toggleMute(); reveal()
                        }
                        CtlButton(Icons.Default.Settings, "Settings") { showSettings = true }
                        if (onFullscreen != null) CtlButton(Icons.Default.Fullscreen, "Full screen") { onFullscreen() }
                    }
                }
            }
        }
    }

    if (showSettings) {
        PlayerSettingsDialog(
            player = player, isLive = current.isLive, aspect = aspect, fill = fill,
            onAspect = { aspect = it; player.setAspectRatio(it) },
            onFill = { fill = it; player.setFill(it) },
            onDismiss = { showSettings = false; reveal() },
        )
    }
}

@Composable
private fun CtlButton(icon: ImageVector, label: String, enabled: Boolean = true, big: Boolean = false, onClick: () -> Unit) {
    IconButton(onClick = onClick, enabled = enabled, modifier = Modifier.alpha(if (enabled) 1f else 0.35f)) {
        Icon(icon, label, tint = Color.White, modifier = Modifier.size(if (big) 32.dp else 24.dp))
    }
}

/** Aspect ratio, fill, playback speed, audio track and subtitles (the macOS gear menu). */
@Composable
private fun PlayerSettingsDialog(
    player: VlcPlayer, isLive: Boolean, aspect: String?, fill: Boolean,
    onAspect: (String?) -> Unit, onFill: (Boolean) -> Unit, onDismiss: () -> Unit,
) {
    var rate by remember { mutableFloatStateOf(1f) }
    var audio by remember { mutableIntStateOf(player.audioTrack) }
    var sub by remember { mutableIntStateOf(player.subtitleTrack) }
    val audioTracks = remember { player.audioTracks() }
    val subTracks = remember { player.subtitleTracks().filter { it.id != -1 } }

    Dialog(onDismissRequest = onDismiss) {
        Column(
            Modifier.clip(RoundedCornerShape(14.dp)).background(Theme.surface).widthIn(max = 420.dp)
                .verticalScroll(rememberScrollState()).padding(18.dp),
        ) {
            SettingsHeader("Aspect Ratio")
            ChipRow(listOf("Default" to null, "16:9" to "16:9", "4:3" to "4:3", "16:10" to "16:10", "21:9" to "21:9", "1:1" to "1:1"),
                aspect) { onAspect(it) }
            SettingsHeader("Screen")
            ChipRow(listOf("Fit" to false, "Fill" to true), fill) { onFill(it) }
            if (!isLive) {
                SettingsHeader("Playback Speed")
                ChipRow(listOf(0.5f, 0.75f, 1f, 1.25f, 1.5f, 2f).map { (if (it == 1f) "Normal" else "${it}×") to it }, rate) {
                    rate = it; player.setRate(it)
                }
            }
            if (audioTracks.isNotEmpty()) {
                SettingsHeader("Audio Track")
                audioTracks.forEach { t ->
                    OptionRow(t.name, t.id == audio) { audio = t.id; player.audioTrack = t.id }
                }
            }
            SettingsHeader("Subtitles")
            OptionRow("Off", sub == -1) { sub = -1; player.subtitleTrack = -1 }
            subTracks.forEach { t -> OptionRow(t.name, t.id == sub) { sub = t.id; player.subtitleTrack = t.id } }
            Spacer(Modifier.height(8.dp))
            Text("Done", color = Theme.accent, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.align(Alignment.End).clip(RoundedCornerShape(8.dp)).clickable(onClick = onDismiss).padding(10.dp))
        }
    }
}

@Composable
private fun SettingsHeader(title: String) {
    Text(title, color = Theme.textTertiary, fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(top = 12.dp, bottom = 6.dp))
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun <T> ChipRow(options: List<Pair<String, T>>, selected: T, onPick: (T) -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        options.forEach { (label, value) ->
            val on = value == selected
            Text(label, color = if (on) Color.White else Theme.textSecondary, fontSize = 13.sp,
                modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(if (on) Theme.accent else Theme.surfaceRaised)
                    .clickable { onPick(value) }.padding(horizontal = 12.dp, vertical = 8.dp))
        }
    }
}

@Composable
private fun OptionRow(label: String, selected: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).clickable(onClick = onClick).padding(vertical = 10.dp, horizontal = 6.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(10.dp).clip(RoundedCornerShape(5.dp)).background(if (selected) Theme.accent else Theme.border))
        Spacer(Modifier.width(12.dp))
        Text(label, color = if (selected) Theme.textPrimary else Theme.textSecondary, fontSize = 14.sp)
    }
}
