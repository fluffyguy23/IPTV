package com.iptvxtreme.player.core

import android.content.Context
import com.iptvxtreme.player.IPTVApp
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.net.URI
import java.util.UUID

/**
 * A saved IPTV connection. The password is NOT stored here — it lives in
 * CredentialStore keyed by `id`. Everything in this class is non-secret metadata.
 */
@Serializable
data class Profile(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    /** Normalized base URL, e.g. "http://host:port" (no trailing slash). */
    val baseURL: String,
    val username: String,
    /** Preferred live container: "ts" or "m3u8". */
    val liveFormat: String = "ts",
    /** Optional user-supplied XMLTV EPG URL. */
    val xmltvURL: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
) {
    val host: String get() = runCatching { URI(baseURL).host }.getOrNull() ?: baseURL
}

object URLNormalizer {
    /**
     * Turn user input into "scheme://host[:port]" with no trailing slash or path.
     * Accepts "host", "host:8080", "http://host/", "https://host:443/c/" etc.
     */
    fun normalizeBase(raw: String): String? {
        var s = raw.trim()
        if (s.isEmpty()) return null
        if (!s.contains("://")) s = "http://$s"
        val uri = runCatching { URI(s) }.getOrNull() ?: return null
        val host = uri.host?.takeIf { it.isNotEmpty() } ?: return null
        val scheme = (uri.scheme ?: "http").lowercase()
        if (scheme != "http" && scheme != "https") return null
        return if (uri.port > 0) "$scheme://$host:${uri.port}" else "$scheme://$host"
    }
}

/**
 * Persists the list of profiles (metadata in SharedPreferences; passwords in
 * CredentialStore) and tracks which profile was used last.
 */
object ProfileStore {
    private const val PROFILES_KEY = "profiles.v1"
    private const val LAST_USED_KEY = "profiles.lastUsed"
    private val prefs get() = IPTVApp.instance.getSharedPreferences("profiles", Context.MODE_PRIVATE)
    private val serializer = ListSerializer(Profile.serializer())

    var profiles: List<Profile> = load()
        private set

    private fun load(): List<Profile> {
        val raw = prefs.getString(PROFILES_KEY, null) ?: return emptyList()
        return runCatching { XtreamClient.json.decodeFromString(serializer, raw) }.getOrDefault(emptyList())
    }

    private fun persist() {
        prefs.edit().putString(PROFILES_KEY, XtreamClient.json.encodeToString(serializer, profiles)).apply()
    }

    /** Create or update a profile, storing the password encrypted. */
    fun save(profile: Profile, password: String?) {
        profiles = if (profiles.any { it.id == profile.id }) {
            profiles.map { if (it.id == profile.id) profile else it }
        } else {
            profiles + profile
        }
        if (!password.isNullOrEmpty()) CredentialStore.set(password, profile.id)
        persist()
    }

    fun delete(profile: Profile) {
        profiles = profiles.filterNot { it.id == profile.id }
        CredentialStore.delete(profile.id)
        if (lastUsedID == profile.id) lastUsedID = null
        persist()
    }

    fun password(profile: Profile): String? = CredentialStore.password(profile.id)

    var lastUsedID: String?
        get() = prefs.getString(LAST_USED_KEY, null)
        set(value) {
            prefs.edit().apply { if (value != null) putString(LAST_USED_KEY, value) else remove(LAST_USED_KEY) }.apply()
        }

    val lastUsedProfile: Profile? get() = lastUsedID?.let { id -> profiles.firstOrNull { it.id == id } }
}
