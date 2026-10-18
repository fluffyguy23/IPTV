package com.iptvxtreme.player.ui.components

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.iptvxtreme.player.ui.Theme

/** Artwork with a centered placeholder glyph behind it (shown while loading or on failure). */
@Composable
fun Artwork(url: String?, placeholder: ImageVector, modifier: Modifier = Modifier, corner: Dp = Theme.corner,
            contentScale: ContentScale = ContentScale.Crop) {
    Box(modifier.clip(RoundedCornerShape(corner)).background(Theme.surfaceRaised), contentAlignment = Alignment.Center) {
        Icon(placeholder, null, tint = Theme.textTertiary, modifier = Modifier.size(32.dp))
        if (!url.isNullOrBlank()) {
            AsyncImage(model = url, contentDescription = null, contentScale = contentScale, modifier = Modifier.fillMaxSize())
        }
    }
}

data class MenuAction(val title: String, val danger: Boolean = false, val action: () -> Unit)

/**
 * A poster tile: artwork, title, subtitle, optional resume-progress bar and rating
 * badge. Long-press opens the item's menu (the macOS right-click menu).
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun PosterCard(
    title: String,
    subtitle: String? = null,
    posterURL: String?,
    placeholder: ImageVector,
    modifier: Modifier = Modifier,
    width: Dp? = Theme.posterWidth,
    aspect: Float = 2f / 3f,
    progress: Float? = null,
    badge: String? = null,
    menu: List<MenuAction> = emptyList(),
    onClick: () -> Unit,
) {
    var menuOpen by remember { mutableStateOf(false) }
    Column(
        (if (width != null) modifier.width(width) else modifier.fillMaxWidth())
            .clip(RoundedCornerShape(Theme.corner))
            .combinedClickable(onClick = onClick, onLongClick = { if (menu.isNotEmpty()) menuOpen = true })
    ) {
        Box(Modifier.fillMaxWidth().aspectRatio(aspect)) {
            Artwork(posterURL, placeholder, Modifier.fillMaxSize())
            if (badge != null) {
                Text(badge, color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold,
                    modifier = Modifier.align(Alignment.TopEnd).padding(6.dp)
                        .background(Theme.accent, RoundedCornerShape(5.dp)).padding(horizontal = 6.dp, vertical = 2.dp))
            }
            if (progress != null && progress > 0.01f) {
                Box(Modifier.align(Alignment.BottomCenter).padding(8.dp).fillMaxWidth().height(3.dp)
                    .background(Color.Black.copy(alpha = 0.55f), RoundedCornerShape(2.dp))) {
                    Box(Modifier.fillMaxWidth(progress.coerceIn(0.03f, 1f)).height(3.dp)
                        .background(Theme.accent, RoundedCornerShape(2.dp)))
                }
            }
            DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false },
                modifier = Modifier.background(Theme.surfaceRaised)) {
                menu.forEach { m ->
                    DropdownMenuItem(text = { Text(m.title, color = if (m.danger) Theme.negative else Theme.textPrimary) },
                        onClick = { menuOpen = false; m.action() })
                }
            }
        }
        Text(title, color = Theme.textPrimary, fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold,
            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(start = 2.dp, end = 2.dp, top = 6.dp))
        if (subtitle != null) {
            Text(subtitle, color = Theme.textTertiary, fontSize = 11.sp, maxLines = 1,
                overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(horizontal = 2.dp))
        }
    }
}

/** Titled horizontal rail of cards. */
@Composable
fun <T> Rail(title: String, items: List<T>, key: ((T) -> Any)? = null, card: @Composable (T) -> Unit) {
    Column(Modifier.fillMaxWidth().padding(bottom = 22.dp)) {
        Text(title, color = Theme.textPrimary, fontSize = 17.sp, fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp))
        LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            items(items, key = key) { card(it) }
        }
    }
}

@Composable
fun LoadingView(message: String = "Loading…", modifier: Modifier = Modifier.fillMaxSize()) {
    Box(modifier, contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            CircularProgressIndicator(color = Theme.accent, strokeWidth = 3.dp, modifier = Modifier.size(34.dp))
            Spacer(Modifier.height(12.dp))
            Text(message, color = Theme.textSecondary, fontSize = 13.sp, fontWeight = FontWeight.Medium)
        }
    }
}

@Composable
fun EmptyStateView(icon: ImageVector, title: String, message: String, modifier: Modifier = Modifier.fillMaxSize(),
                   actionTitle: String? = null, onAction: (() -> Unit)? = null) {
    Box(modifier.padding(24.dp), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.widthIn(max = 420.dp)) {
            Icon(icon, null, tint = Theme.textTertiary, modifier = Modifier.size(48.dp))
            Spacer(Modifier.height(10.dp))
            Text(title, color = Theme.textPrimary, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
            Spacer(Modifier.height(6.dp))
            Text(message, color = Theme.textSecondary, fontSize = 13.5.sp, textAlign = TextAlign.Center)
            if (actionTitle != null && onAction != null) {
                Spacer(Modifier.height(14.dp))
                PillButton(actionTitle, onClick = onAction)
            }
        }
    }
}

/** Rounded accent button (filled or outlined), matching the macOS PillButton. */
@Composable
fun PillButton(title: String, modifier: Modifier = Modifier, filled: Boolean = true, enabled: Boolean = true,
               color: Color = Theme.accent, onClick: () -> Unit) {
    val shape = RoundedCornerShape(9.dp)
    Box(
        modifier.heightIn(min = 42.dp).widthIn(min = 120.dp).clip(shape)
            .background(if (filled) color.copy(alpha = if (enabled) 1f else 0.4f) else Color.Transparent)
            .then(if (filled) Modifier else Modifier.border(1.dp, color, shape))
            .combinedClickableCompat(enabled, onClick)
            .padding(horizontal = 18.dp, vertical = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, color = if (filled) Color.White else color, fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold,
            maxLines = 1)
    }
}

@OptIn(ExperimentalFoundationApi::class)
fun Modifier.combinedClickableCompat(enabled: Boolean = true, onClick: () -> Unit) =
    this.combinedClickable(enabled = enabled, onClick = onClick)

/** Styled single-line text field (search boxes, filters). */
@Composable
fun SearchBox(value: String, onValueChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier,
              onSubmit: (() -> Unit)? = null) {
    Row(
        modifier.height(42.dp).clip(RoundedCornerShape(21.dp)).background(Theme.surface)
            .border(1.dp, Theme.border, RoundedCornerShape(21.dp)).padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Default.Search, null, tint = Theme.textTertiary, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(8.dp))
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
            if (value.isEmpty()) Text(placeholder, color = Theme.textTertiary, fontSize = 14.sp, maxLines = 1)
            BasicTextField(
                value = value, onValueChange = onValueChange, singleLine = true,
                textStyle = TextStyle(color = Theme.textPrimary, fontSize = 14.sp),
                cursorBrush = SolidColor(Theme.accent),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = { onSubmit?.invoke() }),
                modifier = Modifier.fillMaxWidth(),
            )
        }
        if (value.isNotEmpty()) {
            Icon(Icons.Default.Close, "Clear", tint = Theme.textTertiary,
                modifier = Modifier.size(18.dp).combinedClickableCompat { onValueChange("") })
        }
    }
}

/** A compact popup selector (replaces NSPopUpButton). */
@Composable
fun Selector(label: String?, options: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    var open by remember { mutableStateOf(false) }
    Column(modifier) {
        if (label != null) {
            Text(label, color = Theme.textTertiary, fontSize = 11.sp, fontWeight = FontWeight.Medium,
                modifier = Modifier.padding(bottom = 4.dp))
        }
        Box {
            Row(
                Modifier.fillMaxWidth().height(40.dp).clip(RoundedCornerShape(8.dp)).background(Theme.surfaceRaised)
                    .border(1.dp, Theme.border, RoundedCornerShape(8.dp)).combinedClickableCompat { open = true }
                    .padding(start = 12.dp, end = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(options.getOrElse(selected) { "" }, color = Theme.textPrimary, fontSize = 13.5.sp, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                Icon(Icons.Default.ArrowDropDown, null, tint = Theme.textSecondary)
            }
            DropdownMenu(expanded = open, onDismissRequest = { open = false },
                modifier = Modifier.background(Theme.surfaceRaised).heightIn(max = 420.dp)) {
                options.forEachIndexed { i, o ->
                    DropdownMenuItem(
                        text = { Text(o, color = if (i == selected) Theme.accent else Theme.textPrimary, maxLines = 1,
                            overflow = TextOverflow.Ellipsis) },
                        onClick = { open = false; onSelect(i) })
                }
            }
        }
    }
}

/** Bordered card container used by Settings and the connection screen. */
@Composable
fun Card(title: String?, modifier: Modifier = Modifier, titleContent: (@Composable () -> Unit)? = null,
         content: @Composable () -> Unit) {
    Column(
        modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Theme.surface)
            .border(1.dp, Theme.border, RoundedCornerShape(14.dp)).padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        when {
            titleContent != null -> titleContent()
            title != null -> Text(title, color = Theme.textPrimary, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
        }
        content()
    }
}

fun formatDuration(secs: Long): String {
    val h = secs / 3600; val m = (secs % 3600) / 60
    return if (h > 0) "${h}h ${m}m" else "${m}m"
}

fun formatHMS(totalSecs: Double): String {
    val t = totalSecs.coerceAtLeast(0.0).toLong()
    val h = t / 3600; val m = (t % 3600) / 60; val s = t % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
}
