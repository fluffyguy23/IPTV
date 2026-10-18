package com.iptvxtreme.player.player

import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.iptvxtreme.player.IPTVApp
import com.iptvxtreme.player.core.Log
import org.videolan.libvlc.LibVLC
import org.videolan.libvlc.Media
import org.videolan.libvlc.MediaPlayer
import org.videolan.libvlc.util.VLCVideoLayout

/**
 * Thin Compose-observable wrapper over a libVLC MediaPlayer. Events arrive on
 * the main thread and update snapshot state the player UI reads directly.
 */
class VlcPlayer {
    enum class State { Nothing, Opening, Buffering, Playing, Paused, Stopped, Ended, Error }

    data class Track(val id: Int, val name: String)

    private val player = MediaPlayer(libVLC)

    var state by mutableStateOf(State.Nothing); private set
    var timeMs by mutableLongStateOf(0L); private set
    var lengthMs by mutableLongStateOf(0L); private set
    var buffering by mutableFloatStateOf(100f); private set
    var isSeekable by mutableStateOf(false); private set

    /** Called once per event so the owner can react (resume, auto-advance, progress). */
    var onEvent: ((State) -> Unit)? = null

    init {
        player.setEventListener { e ->
            when (e.type) {
                MediaPlayer.Event.Opening -> set(State.Opening)
                MediaPlayer.Event.Buffering -> {
                    buffering = e.buffering
                    if (e.buffering < 100f && state != State.Paused) set(State.Buffering)
                    else if (e.buffering >= 100f && state == State.Buffering) set(State.Playing)
                }
                MediaPlayer.Event.Playing -> set(State.Playing)
                MediaPlayer.Event.Paused -> set(State.Paused)
                MediaPlayer.Event.Stopped -> if (state != State.Ended && state != State.Error) set(State.Stopped)
                MediaPlayer.Event.EndReached -> set(State.Ended)
                MediaPlayer.Event.EncounteredError -> set(State.Error)
                MediaPlayer.Event.TimeChanged -> { timeMs = e.timeChanged; onEvent?.invoke(state) }
                MediaPlayer.Event.LengthChanged -> lengthMs = e.lengthChanged
                MediaPlayer.Event.SeekableChanged -> isSeekable = e.seekable
                MediaPlayer.Event.Vout -> if (e.voutCount > 0 && state != State.Paused) set(State.Playing)
            }
        }
    }

    private fun set(s: State) {
        state = s
        onEvent?.invoke(s)
    }

    fun attach(layout: VLCVideoLayout) {
        if (!player.vlcVout.areViewsAttached()) player.attachViews(layout, null, true, false)
    }

    fun detach() {
        if (player.vlcVout.areViewsAttached()) player.detachViews()
    }

    fun load(url: String, options: List<String>) {
        timeMs = 0; lengthMs = 0; isSeekable = false; buffering = 0f
        state = State.Opening
        val media = Media(libVLC, Uri.parse(url))
        options.forEach { media.addOption(it) }
        media.setHWDecoderEnabled(true, false)
        player.media = media
        media.release()
    }

    fun play() = player.play()
    fun setPaused(paused: Boolean) { if (paused) player.pause() else player.play() }
    val isPlaying get() = player.isPlaying

    fun stop() {
        if (state != State.Nothing) player.stop()
    }

    fun seek(toMs: Long) {
        player.setTime(toMs.coerceAtLeast(0))
        timeMs = toMs.coerceAtLeast(0)
    }

    /** Current position read straight from the engine (event values can lag). */
    val currentTimeMs: Long get() = player.time.takeIf { it >= 0 } ?: timeMs
    val currentLengthMs: Long get() = player.length.takeIf { it > 0 } ?: lengthMs

    var volume: Int
        get() = player.volume
        set(v) { player.setVolume(v.coerceIn(0, 125)) }

    var isMuted by mutableStateOf(false)
        private set
    private var volumeBeforeMute = 100

    fun toggleMute() {
        if (isMuted) { player.setVolume(volumeBeforeMute); isMuted = false }
        else { volumeBeforeMute = player.volume.takeIf { it > 0 } ?: 100; player.setVolume(0); isMuted = true }
    }

    fun setAspectRatio(ratio: String?) {
        player.aspectRatio = ratio
    }

    fun setFill(fill: Boolean) {
        player.videoScale = if (fill) MediaPlayer.ScaleType.SURFACE_FILL else MediaPlayer.ScaleType.SURFACE_BEST_FIT
    }

    fun setRate(rate: Float) { player.rate = rate }

    fun audioTracks(): List<Track> = player.audioTracks?.map { Track(it.id, it.name) } ?: emptyList()
    var audioTrack: Int
        get() = player.audioTrack
        set(id) { player.setAudioTrack(id) }

    fun subtitleTracks(): List<Track> = player.spuTracks?.map { Track(it.id, it.name) } ?: emptyList()
    var subtitleTrack: Int
        get() = player.spuTrack
        set(id) { player.setSpuTrack(id) }

    fun release() {
        onEvent = null
        player.setEventListener(null)
        runCatching { player.stop() }
        detach()
        player.release()
    }

    companion object {
        /** One LibVLC instance per process; creating it is expensive. */
        val libVLC: LibVLC by lazy {
            LibVLC(IPTVApp.instance, arrayListOf(
                "--http-reconnect",
                "--audio-time-stretch",
                "--avcodec-skiploopfilter=1",
                "--no-sub-autodetect-file",
            )).also { Log.info("libVLC initialized") }
        }

        const val version = "3.7.7"
    }
}
