package com.iptvxtreme.player.core

import android.util.Base64
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject

// MARK: - Auth / account

data class UserInfo(
    val username: String?,
    val status: String?,            // "Active", "Expired", "Banned", "Disabled"
    val auth: Long?,                // 1 when authenticated
    val expDateSecs: Long?,         // subscription expiry (unix seconds)
    val isTrial: Boolean?,
    val activeConnections: Long?,
    val maxConnections: Long?,
    val allowedOutputFormats: List<String>?,
) {
    companion object {
        fun parse(o: JsonObject) = UserInfo(
            username = o.str("username"),
            status = o.str("status"),
            auth = o.int("auth"),
            expDateSecs = o.int("exp_date"),
            isTrial = o.bool("is_trial"),
            activeConnections = o.int("active_cons"),
            maxConnections = o.int("max_connections"),
            allowedOutputFormats = o.strList("allowed_output_formats"),
        )
    }
}

data class ServerInfo(
    val url: String?,
    val port: String?,
    val httpsPort: String?,
    val serverProtocol: String?,
    val timezone: String?,
) {
    companion object {
        fun parse(o: JsonObject) = ServerInfo(
            url = o.str("url"),
            port = o.str("port"),
            httpsPort = o.str("https_port"),
            serverProtocol = o.str("server_protocol"),
            timezone = o.str("timezone"),
        )
    }
}

data class AuthResponse(val userInfo: UserInfo?, val serverInfo: ServerInfo?)

// MARK: - Categories

data class Category(val id: String, val name: String) {
    companion object {
        fun parse(o: JsonObject) = Category(
            id = o.str("category_id") ?: "",
            name = o.str("category_name") ?: "Unknown",
        )
    }
}

// MARK: - Live channels

data class LiveStream(
    val streamID: Long,
    val num: Long?,
    val name: String,
    val icon: String?,
    val epgChannelID: String?,
    val categoryID: String?,
    val tvArchive: Boolean,
    val addedTimestamp: Long?,
) {
    companion object {
        fun parse(o: JsonObject) = LiveStream(
            streamID = o.int("stream_id") ?: 0,
            num = o.int("num"),
            name = (o.str("name") ?: "").trim(),
            icon = o.str("stream_icon").nonEmpty(),
            epgChannelID = o.str("epg_channel_id"),
            categoryID = o.str("category_id"),
            tvArchive = (o.int("tv_archive") ?: 0) > 0,
            addedTimestamp = o.int("added"),
        )
    }
}

// MARK: - Movies (VOD)

data class VODStream(
    val streamID: Long,
    val num: Long?,
    val name: String,
    val icon: String?,
    val rating5: Double?,
    val categoryID: String?,
    val containerExtension: String?,
    val addedTimestamp: Long?,
) {
    companion object {
        fun parse(o: JsonObject) = VODStream(
            streamID = o.int("stream_id") ?: 0,
            num = o.int("num"),
            name = (o.str("name") ?: "").trim(),
            icon = o.str("stream_icon").nonEmpty(),
            rating5 = o.dbl("rating_5based"),
            categoryID = o.str("category_id"),
            containerExtension = o.str("container_extension").nonEmpty(),
            addedTimestamp = o.int("added"),
        )
    }
}

/** Full detail for a single movie (get_vod_info). */
data class VODInfo(
    val name: String?,
    val plot: String?,
    val cast: String?,
    val director: String?,
    val genre: String?,
    val releaseDate: String?,
    val rating: String?,
    val durationSecs: Long?,
    val posterPath: String?,
    val containerExtension: String?,
) {
    companion object {
        fun parse(root: JsonObject): VODInfo {
            val info = root.obj("info")
            val movieData = root.obj("movie_data")
            return VODInfo(
                name = info?.str("name").nonEmpty(),
                plot = (info?.str("plot") ?: info?.str("description")).nonEmpty(),
                cast = info?.str("cast").nonEmpty(),
                director = info?.str("director").nonEmpty(),
                genre = info?.str("genre").nonEmpty(),
                releaseDate = (info?.str("release_date") ?: info?.str("releasedate")).nonEmpty(),
                rating = info?.str("rating").nonEmpty(),
                durationSecs = info?.int("duration_secs"),
                posterPath = (info?.str("movie_image") ?: info?.str("cover_big")).nonEmpty(),
                containerExtension = movieData?.str("container_extension").nonEmpty(),
            )
        }
    }
}

// MARK: - Series

data class SeriesStream(
    val seriesID: Long,
    val name: String,
    val cover: String?,
    val plot: String?,
    val genre: String?,
    val cast: String?,
    val director: String?,
    val releaseDate: String?,
    val rating5: Double?,
    val categoryID: String?,
    val lastModified: Long?,
) {
    companion object {
        fun parse(o: JsonObject) = SeriesStream(
            seriesID = o.int("series_id") ?: 0,
            name = (o.str("name") ?: "").trim(),
            cover = o.str("cover").nonEmpty(),
            plot = o.str("plot").nonEmpty(),
            genre = o.str("genre").nonEmpty(),
            cast = o.str("cast").nonEmpty(),
            director = o.str("director").nonEmpty(),
            releaseDate = o.str("releaseDate").nonEmpty(),
            rating5 = o.dbl("rating_5based"),
            categoryID = o.str("category_id"),
            lastModified = o.int("last_modified"),
        )
    }
}

data class Episode(
    val id: String,
    val episodeNum: Long,
    val title: String,
    val containerExtension: String?,
    val plot: String?,
    val durationSecs: Long?,
    val image: String?,
    val season: Long,
) {
    companion object {
        fun parse(o: JsonObject, fallbackSeason: Long): Episode {
            val info = o.obj("info")
            return Episode(
                id = o.str("id") ?: "",
                episodeNum = o.int("episode_num") ?: 0,
                title = (o.str("title") ?: "").trim(),
                containerExtension = o.str("container_extension").nonEmpty(),
                plot = info?.str("plot").nonEmpty(),
                durationSecs = info?.int("duration_secs"),
                image = info?.str("movie_image").nonEmpty(),
                season = o.int("season") ?: fallbackSeason,
            )
        }
    }
}

/** get_series_info: series metadata + episodes grouped by season. */
data class SeriesInfo(
    val plot: String?,
    val cast: String?,
    val director: String?,
    val genre: String?,
    val releaseDate: String?,
    val rating: String?,
    val cover: String?,
    /** Season number -> ordered episodes. */
    val episodesBySeason: Map<Long, List<Episode>>,
) {
    val sortedSeasons: List<Long> get() = episodesBySeason.keys.sorted()

    companion object {
        fun parse(root: JsonObject): SeriesInfo {
            val info = root.obj("info")
            // "episodes": { "1": [ {..}, {..} ], "2": [ ... ] }  (some servers send an array of arrays)
            val grouped = mutableMapOf<Long, List<Episode>>()
            when (val eps = root["episodes"]) {
                is JsonObject -> for ((key, value) in eps) {
                    val season = key.trim().toLongOrNull() ?: 0
                    val list = value.objects().map { Episode.parse(it, season) }
                    if (list.isNotEmpty()) grouped[season] = list.sortedBy { it.episodeNum }
                }
                is JsonArray -> eps.forEachIndexed { idx, value ->
                    val list = value.objects().map { Episode.parse(it, (idx + 1).toLong()) }
                    if (list.isNotEmpty()) grouped[list.first().season] = list.sortedBy { it.episodeNum }
                }
                else -> {}
            }
            return SeriesInfo(
                plot = info?.str("plot").nonEmpty(),
                cast = info?.str("cast").nonEmpty(),
                director = info?.str("director").nonEmpty(),
                genre = info?.str("genre").nonEmpty(),
                releaseDate = info?.str("releaseDate").nonEmpty(),
                rating = info?.str("rating").nonEmpty(),
                cover = info?.str("cover").nonEmpty(),
                episodesBySeason = grouped,
            )
        }
    }
}

// MARK: - EPG

data class EPGEntry(val title: String, val description: String, val startSecs: Long?, val endSecs: Long?) {
    companion object {
        fun parse(o: JsonObject) = EPGEntry(
            title = decodeBase64(o.str("title")),
            description = decodeBase64(o.str("description")),
            startSecs = o.int("start_timestamp"),
            endSecs = o.int("stop_timestamp"),
        )

        /** Xtream base64-encodes EPG title/description. */
        private fun decodeBase64(s: String?): String {
            if (s.isNullOrEmpty()) return ""
            return try {
                String(Base64.decode(s, Base64.DEFAULT), Charsets.UTF_8)
            } catch (e: IllegalArgumentException) {
                s
            }
        }
    }
}
