package com.iptvxtreme.player.core

import android.net.Uri
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.DecodeSequenceMode
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.decodeToSequence
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.net.SocketTimeoutException
import java.net.URI
import java.util.concurrent.TimeUnit

/**
 * Talks to the Xtream Codes `player_api.php` endpoint and builds stream URLs.
 * Networking is async; identical in-flight requests are coalesced to avoid
 * duplicate downloads (e.g. when several screens load the same list at once).
 * Large lists are streamed to disk and parsed incrementally to keep memory low.
 */
class XtreamClient(val baseURL: String, val username: String, private val password: String) {

    /**
     * Base used for building stream URLs. Many providers answer the API on one
     * port (e.g. 80) but serve streams on the port advertised in server_info
     * (e.g. 8080). Defaults to baseURL until resolveStreamBase runs after auth.
     */
    @Volatile var streamBase: String = baseURL
        private set

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val lock = Mutex()
    private val inFlight = mutableMapOf<String, Deferred<Any>>()

    // MARK: - URL building

    private fun apiURL(action: String?, extra: Map<String, String> = emptyMap()): HttpUrl {
        val base = "$baseURL/player_api.php".toHttpUrlOrNull() ?: throw XtreamError.InvalidUrl
        return base.newBuilder().apply {
            addQueryParameter("username", username)
            addQueryParameter("password", password)
            action?.let { addQueryParameter("action", it) }
            extra.forEach { (k, v) -> addQueryParameter(k, v) }
        }.build()
    }

    private fun seg(s: String) = Uri.encode(s)

    /**
     * Derive the stream base from server_info: keep the host (and scheme) the
     * user connected to, but use the provider-advertised port for streams.
     */
    fun resolveStreamBase(server: ServerInfo?) {
        val uri = runCatching { URI(baseURL) }.getOrNull()
        val host = uri?.host
        if (server == null || uri == null || host == null) { streamBase = baseURL; return }
        val scheme = uri.scheme ?: "http"
        val advertised = if (scheme == "https") (server.httpsPort ?: server.port) else server.port
        streamBase = when {
            !advertised.isNullOrEmpty() && advertised != "0" -> "$scheme://$host:$advertised"
            uri.port > 0 -> "$scheme://$host:${uri.port}"
            else -> "$scheme://$host"
        }
        Log.info("Stream base resolved to ${Log.redact(streamBase)}")
    }

    /** Live stream playback URL. `format` is "ts" or "m3u8". */
    fun liveURL(streamID: Long, format: String) =
        "$streamBase/live/${seg(username)}/${seg(password)}/$streamID.$format"

    /** Movie (VOD) playback URL. */
    fun movieURL(streamID: Long, ext: String?) =
        "$streamBase/movie/${seg(username)}/${seg(password)}/$streamID.${ext.nonEmpty() ?: "mp4"}"

    /** Series episode playback URL. */
    fun episodeURL(episodeID: String, ext: String?) =
        "$streamBase/series/${seg(username)}/${seg(password)}/$episodeID.${ext.nonEmpty() ?: "mp4"}"

    // MARK: - Core fetch (with de-duplication)

    @Suppress("UNCHECKED_CAST")
    private suspend fun <T : Any> dedup(key: String, block: suspend () -> T): T {
        val deferred = lock.withLock {
            // The cleanup needs the lock we hold here, so it always runs after the put.
            inFlight[key] ?: scope.async<Any> {
                try { block() } finally { withContext(NonCancellable) { lock.withLock { inFlight.remove(key) } } }
            }.also { inFlight[key] = it }
        }
        return deferred.await() as T
    }

    private fun request(url: HttpUrl) = Request.Builder()
        .url(url)
        .header("User-Agent", "IPTVXtremePlayer/1.1 (Android)")
        .build()

    private inline fun <T> mapErrors(block: () -> T): T = try {
        block()
    } catch (e: XtreamError) {
        throw e
    } catch (e: SocketTimeoutException) {
        throw XtreamError.Timeout
    } catch (e: IOException) {
        throw XtreamError.Network(e.message ?: "connection failed")
    }

    /** Small responses: read fully into memory. */
    private suspend fun fetchBytes(url: HttpUrl): ByteArray = dedup(url.toString()) {
        withContext(Dispatchers.IO) {
            mapErrors {
                http.newCall(request(url)).execute().use { resp ->
                    if (!resp.isSuccessful) throw XtreamError.HttpStatus(resp.code)
                    resp.body?.bytes() ?: ByteArray(0)
                }
            }
        }
    }

    /** Large responses: stream to `dest` atomically (temp file then rename). */
    suspend fun download(action: String, dest: File) {
        val url = apiURL(action)
        dedup<Unit>("dl:" + url.toString()) {
            withContext(Dispatchers.IO) {
                mapErrors {
                    http.newCall(request(url)).execute().use { resp ->
                        if (!resp.isSuccessful) throw XtreamError.HttpStatus(resp.code)
                        val body = resp.body ?: throw XtreamError.Empty
                        dest.parentFile?.mkdirs()
                        val tmp = File(dest.parentFile, dest.name + ".part")
                        tmp.outputStream().use { out -> body.byteStream().copyTo(out, 64 * 1024) }
                        if (tmp.length() == 0L) { tmp.delete(); throw XtreamError.Empty }
                        if (!tmp.renameTo(dest)) { dest.delete(); tmp.renameTo(dest) }
                    }
                }
            }
        }
    }

    // MARK: - Public API

    /**
     * Authenticate and return account info. Throws for bad credentials,
     * expired/banned subscriptions, or unreachable servers.
     */
    suspend fun authenticate(): AuthResponse {
        val data = fetchBytes(apiURL(null))
        if (data.isEmpty()) throw XtreamError.Empty
        val root = try {
            json.parseToJsonElement(String(data, Charsets.UTF_8)) as? JsonObject
        } catch (e: SerializationException) {
            null
        } ?: throw XtreamError.AuthFailed  // many panels answer bad creds with a non-JSON body
        val user = root.obj("user_info")?.let(UserInfo::parse) ?: throw XtreamError.AuthFailed
        val server = root.obj("server_info")?.let(ServerInfo::parse)
        if (user.auth == 0L) throw XtreamError.AuthFailed
        when ((user.status ?: "").lowercase()) {
            "expired" -> throw XtreamError.SubscriptionExpired
            "banned", "disabled" -> throw XtreamError.SubscriptionBanned
        }
        // Some servers omit the auth flag but still return a username on success.
        if (user.auth == null && user.username.isNullOrEmpty()) throw XtreamError.AuthFailed
        return AuthResponse(user, server)
    }

    suspend fun liveStreams(categoryID: String) =
        listFrom(fetchBytes(apiURL("get_live_streams", mapOf("category_id" to categoryID))), LiveStream::parse).distinctBy { it.streamID }

    suspend fun vodStreams(categoryID: String) =
        listFrom(fetchBytes(apiURL("get_vod_streams", mapOf("category_id" to categoryID))), VODStream::parse).distinctBy { it.streamID }

    suspend fun series(categoryID: String) =
        listFrom(fetchBytes(apiURL("get_series", mapOf("category_id" to categoryID))), SeriesStream::parse).distinctBy { it.seriesID }

    suspend fun vodInfo(streamID: Long): VODInfo =
        VODInfo.parse(parseObject(fetchBytes(apiURL("get_vod_info", mapOf("vod_id" to streamID.toString())))))

    suspend fun seriesInfo(seriesID: Long): SeriesInfo =
        SeriesInfo.parse(parseObject(fetchBytes(apiURL("get_series_info", mapOf("series_id" to seriesID.toString())))))

    suspend fun shortEPG(streamID: Long, limit: Int = 8): List<EPGEntry> = try {
        val root = parseObject(fetchBytes(apiURL("get_short_epg", mapOf("stream_id" to streamID.toString(), "limit" to limit.toString()))))
        root["epg_listings"]?.objects()?.map(EPGEntry::parse) ?: emptyList()
    } catch (e: XtreamError) {
        if (e is XtreamError.MalformedResponse || e is XtreamError.Empty) emptyList() else throw e
    }

    private fun <T> listFrom(data: ByteArray, map: (JsonObject) -> T): List<T> =
        if (data.isEmpty()) emptyList() else parseList(data.inputStream(), map)

    private fun parseObject(data: ByteArray): JsonObject {
        if (data.isEmpty()) throw XtreamError.Empty
        return try {
            json.parseToJsonElement(String(data, Charsets.UTF_8)) as? JsonObject ?: throw XtreamError.MalformedResponse
        } catch (e: SerializationException) {
            throw XtreamError.MalformedResponse
        }
    }

    companion object {
        val json = Json { ignoreUnknownKeys = true; isLenient = true }

        private val http: OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(40, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)
            .followRedirects(true)
            .build()

        /** Incrementally parse a top-level JSON array of objects without building the whole tree. */
        @OptIn(ExperimentalSerializationApi::class)
        fun <T> parseList(input: InputStream, map: (JsonObject) -> T): List<T> = input.buffered().use { s ->
            try {
                json.decodeToSequence(s, JsonObject.serializer(), DecodeSequenceMode.ARRAY_WRAPPED).map(map).toList()
            } catch (e: SerializationException) {
                throw XtreamError.MalformedResponse
            } catch (e: IllegalArgumentException) {
                throw XtreamError.MalformedResponse
            }
        }
    }
}
