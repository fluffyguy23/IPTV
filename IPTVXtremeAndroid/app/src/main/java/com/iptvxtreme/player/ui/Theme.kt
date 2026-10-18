package com.iptvxtreme.player.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/**
 * Central visual language, identical to the macOS app: black background,
 * dark charcoal surfaces, electric-blue accent, white / light-gray text.
 */
object Theme {
    // Backgrounds
    val background = Color(0xFF0B0E12)       // near-black
    val surface = Color(0xFF15191F)          // dark charcoal
    val surfaceRaised = Color(0xFF1D222A)    // cards / pressed
    val surfaceHover = Color(0xFF252B34)
    val sidebar = Color(0xFF0E1217)
    val border = Color(0xFF2A313B)

    // Accent (electric blue)
    val accent = Color(0xFF2E9BFF)
    val accentDim = Color(0xFF1B6FC0)
    val accentSoft = Color(0x262E9BFF)       // accent @ 15%

    // Text
    val textPrimary = Color(0xFFFFFFFF)
    val textSecondary = Color(0xFFA7B2BF)
    val textTertiary = Color(0xFF6C7682)

    // Status
    val positive = Color(0xFF37D67A)
    val warning = Color(0xFFFFB020)
    val negative = Color(0xFFFF5A5F)

    // Metrics
    val corner = 10.dp
    val sidebarWidth = 212.dp
    val topBarHeight = 56.dp
    val posterWidth = 124.dp
    val posterHeight = 186.dp
}

private val scheme = darkColorScheme(
    primary = Theme.accent,
    onPrimary = Color.White,
    secondary = Theme.accentDim,
    background = Theme.background,
    onBackground = Theme.textPrimary,
    surface = Theme.surface,
    onSurface = Theme.textPrimary,
    surfaceVariant = Theme.surfaceRaised,
    onSurfaceVariant = Theme.textSecondary,
    surfaceContainer = Theme.surface,
    surfaceContainerHigh = Theme.surfaceRaised,
    surfaceContainerHighest = Theme.surfaceHover,
    outline = Theme.border,
    outlineVariant = Theme.border,
    error = Theme.negative,
)

@Composable
fun IPTVTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = scheme, typography = Typography(), content = content)
}
