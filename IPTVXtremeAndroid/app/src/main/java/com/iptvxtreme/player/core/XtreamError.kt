package com.iptvxtreme.player.core

sealed class XtreamError(message: String) : Exception(message) {
    object InvalidUrl : XtreamError("The server address is not valid.")
    class Network(detail: String) : XtreamError("Network error: $detail")
    object Timeout : XtreamError("The server did not respond in time.")
    class HttpStatus(code: Int) : XtreamError("The server returned an error (HTTP $code).")
    object AuthFailed : XtreamError("Incorrect username or password.")
    object SubscriptionExpired : XtreamError("This subscription has expired.")
    object SubscriptionBanned : XtreamError("This account is banned or disabled.")
    object MalformedResponse : XtreamError("The server sent an unexpected response.")
    object Empty : XtreamError("The server returned no data.")
}

/** User-facing text for any error. */
fun Throwable.userMessage(): String = when (this) {
    is XtreamError -> message ?: "Something went wrong."
    else -> message ?: "Something went wrong."
}
