package com.iptvxtreme.player.ui

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.ui.graphics.toArgb
import com.iptvxtreme.player.player.PlayerActivity

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(Theme.background.toArgb()),
        )
        super.onCreate(savedInstanceState)
        setContent {
            IPTVTheme {
                AppRoot(launchPlayer = { item, navigator -> PlayerActivity.launch(this, item, navigator) })
            }
        }
    }
}
