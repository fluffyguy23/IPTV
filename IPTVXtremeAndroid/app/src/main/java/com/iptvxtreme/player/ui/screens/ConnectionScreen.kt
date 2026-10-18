package com.iptvxtreme.player.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.iptvxtreme.player.core.AppState
import com.iptvxtreme.player.core.Profile
import com.iptvxtreme.player.core.ProfileStore
import com.iptvxtreme.player.core.URLNormalizer
import com.iptvxtreme.player.core.userMessage
import com.iptvxtreme.player.ui.Theme
import com.iptvxtreme.player.ui.components.Card
import com.iptvxtreme.player.ui.components.PillButton
import kotlinx.coroutines.launch

/**
 * Shown when no session is active: manage saved profiles and connect. Handles
 * create / edit / delete / connect, with inline validation and error display.
 * Fields always start empty — no credentials are ever bundled with the app.
 */
@Composable
fun ConnectionScreen(initialError: String? = null) {
    val scope = rememberCoroutineScope()
    var profiles by remember { mutableStateOf(ProfileStore.profiles) }
    var editing by remember { mutableStateOf<Profile?>(null) }
    var name by remember { mutableStateOf("") }
    var url by remember { mutableStateOf("") }
    var user by remember { mutableStateOf("") }
    var pass by remember { mutableStateOf("") }
    var showPass by remember { mutableStateOf(false) }
    var format by remember { mutableIntStateOf(0) }
    var xmltv by remember { mutableStateOf("") }
    var error by remember { mutableStateOf(initialError) }
    var busy by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf<Profile?>(null) }

    fun resetForm() {
        editing = null; name = ""; url = ""; user = ""; pass = ""; xmltv = ""; format = 0; error = null; showPass = false
    }

    fun connect(profile: Profile) {
        busy = true; error = null
        scope.launch {
            try {
                AppState.connect(profile)   // session change swaps the whole screen
            } catch (e: Exception) {
                busy = false
                error = e.userMessage()
            }
        }
    }

    fun submit(andConnect: Boolean) {
        error = null
        val base = URLNormalizer.normalizeBase(url)
            ?: return run { error = "Please enter a valid server URL, like http://example.com:8080" }
        val u = user.trim()
        if (u.isEmpty()) return run { error = "Username is required." }
        val existing = editing?.let { ProfileStore.password(it) }
        if (pass.isEmpty() && existing == null) return run { error = "Password is required." }

        val profile = Profile(
            id = editing?.id ?: java.util.UUID.randomUUID().toString(),
            name = name.trim().ifEmpty { Profile(name = "", baseURL = base, username = u).host },
            baseURL = base,
            username = u,
            liveFormat = if (format == 1) "m3u8" else "ts",
            xmltvURL = xmltv.trim().ifEmpty { null },
            createdAt = editing?.createdAt ?: System.currentTimeMillis(),
        )
        ProfileStore.save(profile, pass.ifEmpty { null })
        profiles = ProfileStore.profiles
        if (andConnect) connect(profile) else resetForm()
    }

    Box(Modifier.fillMaxSize().background(Theme.background), contentAlignment = Alignment.TopCenter) {
        Column(
            Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing).imePadding()
                .verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Row {
                    Text("IPTV", color = Theme.textPrimary, fontSize = 28.sp, fontWeight = FontWeight.Bold)
                    Text("Xtreme", color = Theme.accent, fontSize = 28.sp, fontWeight = FontWeight.Bold)
                    Text("Player", color = Theme.textPrimary, fontSize = 28.sp, fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.height(6.dp))
                Text("Connect to your Xtream Codes service", color = Theme.textSecondary, fontSize = 14.sp,
                    textAlign = TextAlign.Center)
            }

            Card("Saved Profiles", Modifier.widthIn(max = 560.dp)) {
                if (profiles.isEmpty()) {
                    Text("No profiles yet. Add one below to get started.", color = Theme.textTertiary, fontSize = 13.sp)
                }
                profiles.forEach { p ->
                    ProfileRow(p, enabled = !busy,
                        onConnect = { connect(p) },
                        onEdit = {
                            editing = p; name = p.name; url = p.baseURL; user = p.username
                            pass = ""   // never echo the stored password back; blank keeps it
                            xmltv = p.xmltvURL ?: ""; format = if (p.liveFormat == "m3u8") 1 else 0; error = null
                        },
                        onDelete = { deleting = p })
                }
            }

            Card(null, Modifier.widthIn(max = 560.dp), titleContent = {
                Text(if (editing != null) "Edit Profile" else "Add a Profile", color = Theme.textPrimary,
                    fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
            }) {
                Field("Profile Name", name, { name = it }, "e.g. Living Room")
                Field("Server URL", url, { url = it }, "http://server-address:port", keyboard = KeyboardType.Uri)
                Field("Username", user, { user = it }, "Username")
                Field(
                    "Password", pass, { pass = it },
                    if (editing != null) "Leave blank to keep the saved password" else "Password",
                    keyboard = KeyboardType.Password,
                    visual = if (showPass) VisualTransformation.None else PasswordVisualTransformation(),
                    trailing = {
                        IconButton(onClick = { showPass = !showPass }) {
                            Icon(if (showPass) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                                if (showPass) "Hide password" else "Show password", tint = Theme.textTertiary)
                        }
                    },
                )
                Column {
                    Text("Live Stream Format", color = Theme.textSecondary, fontSize = 12.sp, fontWeight = FontWeight.Medium,
                        modifier = Modifier.padding(bottom = 6.dp))
                    SingleChoiceSegmentedButtonRow(Modifier.width(220.dp)) {
                        listOf("TS", "M3U8").forEachIndexed { i, label ->
                            SegmentedButton(
                                selected = format == i, onClick = { format = i },
                                shape = SegmentedButtonDefaults.itemShape(i, 2),
                                colors = SegmentedButtonDefaults.colors(
                                    activeContainerColor = Theme.accent, activeContentColor = androidx.compose.ui.graphics.Color.White,
                                    inactiveContainerColor = Theme.surfaceRaised, inactiveContentColor = Theme.textSecondary,
                                    activeBorderColor = Theme.accent, inactiveBorderColor = Theme.border),
                                icon = {},
                            ) { Text(label) }
                        }
                    }
                }
                Field("XMLTV EPG (optional)", xmltv, { xmltv = it }, "Optional XMLTV EPG URL", keyboard = KeyboardType.Uri)

                error?.let { Text(it, color = Theme.negative, fontSize = 13.sp, fontWeight = FontWeight.Medium) }

                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    PillButton("Save & Connect", enabled = !busy) { if (!busy) submit(true) }
                    PillButton(if (editing != null) "Save Changes" else "Save Only", filled = false, enabled = !busy) {
                        if (!busy) submit(false)
                    }
                    if (busy) CircularProgressIndicator(color = Theme.accent, strokeWidth = 2.dp, modifier = Modifier.size(22.dp))
                }
                if (editing != null) {
                    TextButton(onClick = { resetForm() }) { Text("Cancel editing", color = Theme.textSecondary) }
                }
            }
        }
    }

    deleting?.let { p ->
        AlertDialog(
            onDismissRequest = { deleting = null },
            containerColor = Theme.surface,
            title = { Text("Delete \"${p.name}\"?", color = Theme.textPrimary) },
            text = { Text("This removes the profile and its stored password from this device.", color = Theme.textSecondary) },
            confirmButton = {
                TextButton(onClick = {
                    ProfileStore.delete(p)
                    if (editing?.id == p.id) resetForm()
                    profiles = ProfileStore.profiles
                    deleting = null
                }) { Text("Delete", color = Theme.negative) }
            },
            dismissButton = { TextButton(onClick = { deleting = null }) { Text("Cancel", color = Theme.accent) } },
        )
    }
}

@Composable
private fun Field(
    label: String, value: String, onChange: (String) -> Unit, placeholder: String,
    keyboard: KeyboardType = KeyboardType.Text,
    visual: VisualTransformation = VisualTransformation.None,
    trailing: (@Composable () -> Unit)? = null,
) {
    Column(Modifier.fillMaxWidth()) {
        Text(label, color = Theme.textSecondary, fontSize = 12.sp, fontWeight = FontWeight.Medium,
            modifier = Modifier.padding(bottom = 6.dp))
        OutlinedTextField(
            value = value, onValueChange = onChange, singleLine = true,
            placeholder = { Text(placeholder, color = Theme.textTertiary, fontSize = 14.sp) },
            visualTransformation = visual,
            trailingIcon = trailing,
            keyboardOptions = KeyboardOptions(keyboardType = keyboard, imeAction = ImeAction.Next,
                capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false),
            shape = RoundedCornerShape(8.dp),
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = Theme.textPrimary, unfocusedTextColor = Theme.textPrimary,
                focusedContainerColor = Theme.surfaceRaised, unfocusedContainerColor = Theme.surfaceRaised,
                focusedBorderColor = Theme.accent, unfocusedBorderColor = Theme.border, cursorColor = Theme.accent),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/** A saved-profile row with connect / edit / delete. */
@Composable
private fun ProfileRow(p: Profile, enabled: Boolean, onConnect: () -> Unit, onEdit: () -> Unit, onDelete: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(Theme.surfaceRaised)
            .padding(start = 14.dp, end = 4.dp, top = 8.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(p.name, color = Theme.textPrimary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(p.host, color = Theme.textTertiary, fontSize = 11.5.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        PillButton("Connect", enabled = enabled, modifier = Modifier.widthIn(min = 96.dp)) { if (enabled) onConnect() }
        IconButton(onClick = onEdit) { Icon(Icons.Default.Edit, "Edit", tint = Theme.textSecondary, modifier = Modifier.size(20.dp)) }
        IconButton(onClick = onDelete) { Icon(Icons.Default.Delete, "Delete", tint = Theme.textSecondary, modifier = Modifier.size(20.dp)) }
    }
}
