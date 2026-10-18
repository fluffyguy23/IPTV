package com.iptvxtreme.player.core

import android.util.Log as ALog

/** Logging that never prints credentials: URLs are redacted before output. */
object Log {
    private const val TAG = "IPTVXtreme"

    fun info(msg: String) { ALog.i(TAG, redact(msg)) }
    fun error(msg: String) { ALog.e(TAG, redact(msg)) }

    private val queryCred = Regex("(?i)(username|password)=[^&\\s]+")
    private val pathCred = Regex("/(live|movie|series)/[^/\\s]+/[^/\\s]+/")

    /** Strip username/password from query strings and stream paths. */
    fun redact(s: String): String =
        s.replace(queryCred) { "${it.groupValues[1]}=***" }
            .replace(pathCred) { "/${it.groupValues[1]}/***/***/" }
}
