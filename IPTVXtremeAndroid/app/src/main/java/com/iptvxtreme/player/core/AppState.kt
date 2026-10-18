package com.iptvxtreme.player.core

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Global app state: the current connected session (if any). The UI observes
 * [session] to switch between the connection screen and the library.
 */
object AppState {
    var session by mutableStateOf<Session?>(null)
        private set

    /** Set once per process so auto-connect runs only on a cold start. */
    var autoConnectTried = false

    /** Authenticate against a profile (reads its stored password) and install the session. */
    suspend fun connect(profile: Profile) {
        val password = withContext(Dispatchers.IO) { ProfileStore.password(profile) } ?: throw XtreamError.AuthFailed
        connect(profile, password)
    }

    suspend fun connect(profile: Profile, password: String) {
        val client = XtreamClient(profile.baseURL, profile.username, password)
        val auth = client.authenticate()
        // Streams may live on the provider-advertised port even when the API
        // answers elsewhere (e.g. API on :80, streams on :8080).
        client.resolveStreamBase(auth.serverInfo)
        val newSession = Session(profile, client, auth)
        session?.close()
        session = newSession
        ProfileStore.lastUsedID = profile.id
        newSession.warmIndexes()
    }

    fun disconnect() {
        session?.close()
        session = null
        ProfileStore.lastUsedID = null
    }
}
