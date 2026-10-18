package com.iptvxtreme.player.player

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.iptvxtreme.player.core.AppState
import com.iptvxtreme.player.ui.IPTVTheme

/**
 * Full-screen, landscape, immersive player for movies, episodes and full-screen
 * live TV. The item is handed over in memory (its URL contains credentials, so
 * it is never put in an Intent extra).
 */
class PlayerActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val request = pending
        val session = AppState.session
        if (request == null || session == null) { finish(); return }   // e.g. restored after process death

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
        WindowCompat.setDecorFitsSystemWindows(window, false)
        hideSystemBars()

        setContent {
            IPTVTheme {
                BackHandler { finish() }
                PlayerSurface(
                    session = session,
                    item = request.item,
                    embedded = false,
                    navigator = request.navigator,
                    onClose = { finish() },
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemBars()
    }

    private fun hideSystemBars() {
        WindowInsetsControllerCompat(window, window.decorView).apply {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        if (isFinishing) pending = null
    }

    private class Request(val item: PlaybackItem, val navigator: EpisodeNavigator?)

    companion object {
        private var pending: Request? = null

        fun launch(context: Context, item: PlaybackItem, navigator: EpisodeNavigator?) {
            pending = Request(item, navigator)
            context.startActivity(Intent(context, PlayerActivity::class.java))
        }
    }
}
