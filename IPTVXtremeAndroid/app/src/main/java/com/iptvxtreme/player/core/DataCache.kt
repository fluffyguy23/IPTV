package com.iptvxtreme.player.core

import com.iptvxtreme.player.IPTVApp
import java.io.File

/**
 * On-disk cache of raw API responses, with optional max age.
 * Keyed per profile so switching accounts never mixes content.
 */
class DataCache(namespace: String) {
    private val folder = File(root, namespace).apply { mkdirs() }

    fun file(key: String) = File(folder, "$key.json")

    /** The cached file if present and (when maxAgeMs is given) still fresh. */
    fun fresh(key: String, maxAgeMs: Long?): File? {
        val f = file(key)
        if (!f.exists() || f.length() == 0L) return null
        if (maxAgeMs != null && System.currentTimeMillis() - f.lastModified() > maxAgeMs) return null
        return f
    }

    fun clear() {
        folder.deleteRecursively()
        folder.mkdirs()
    }

    companion object {
        val root: File get() = File(IPTVApp.instance.noBackupFilesDir, "DataCache")
    }
}
