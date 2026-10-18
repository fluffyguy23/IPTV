package com.iptvxtreme.player.core

import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CoreTest {
    @Test fun normalizesServerUrls() {
        assertEquals("http://example.com", URLNormalizer.normalizeBase("example.com"))
        assertEquals("http://example.com:8080", URLNormalizer.normalizeBase(" example.com:8080/ "))
        assertEquals("https://host:443", URLNormalizer.normalizeBase("https://host:443/c/"))
        assertNull(URLNormalizer.normalizeBase(""))
        assertNull(URLNormalizer.normalizeBase("ftp://host"))
    }

    @Test fun redactsCredentialsFromUrls() {
        val api = Log.redact("http://h/player_api.php?username=alice&password=s3cret&action=x")
        assertFalse(api.contains("alice")); assertFalse(api.contains("s3cret"))
        val stream = Log.redact("http://h:8080/live/alice/s3cret/123.ts")
        assertEquals("http://h:8080/live/***/***/123.ts", stream)
    }

    @Test fun parsesInconsistentFieldTypesLeniently() {
        val o = XtreamClient.json.parseToJsonElement(
            """{"stream_id":"42","num":7,"name":"  News ","rating_5based":"4.5","tv_archive":"1","added":1700000000.0}"""
        ) as JsonObject
        val live = LiveStream.parse(o)
        assertEquals(42L, live.streamID)
        assertEquals("News", live.name)
        assertTrue(live.tvArchive)
        assertEquals(4.5, VODStream.parse(o).rating5!!, 0.001)
    }

    @Test fun parsesListsIncrementally() {
        val json = """[{"stream_id":1,"name":"A"},{"stream_id":"2","name":"B"}]"""
        val list = XtreamClient.parseList(json.byteInputStream(), VODStream::parse)
        assertEquals(listOf(1L, 2L), list.map { it.streamID })
    }

    @Test fun seriesEpisodesGroupBySeasonInOrder() {
        val root = XtreamClient.json.parseToJsonElement(
            """{"info":{"plot":"p"},"episodes":{"2":[{"id":"b","episode_num":1,"season":2}],
               "1":[{"id":"a2","episode_num":2,"season":1},{"id":"a1","episode_num":1,"season":1}]}}"""
        ) as JsonObject
        val info = SeriesInfo.parse(root)
        assertEquals(listOf(1L, 2L), info.sortedSeasons)
        assertEquals(listOf("a1", "a2"), info.episodesBySeason[1L]!!.map { it.id })
    }

    @Test fun historyFinishedRule() {
        val ref = MediaRef(MediaRef.Kind.movie, streamID = 1, title = "t")
        assertTrue(HistoryEntry(ref, 950.0, 1000.0, 0).isFinished)
        assertFalse(HistoryEntry(ref, 100.0, 1000.0, 0).isFinished)
        assertFalse(MediaRef.series(SeriesStream(5, "s", null, null, null, null, null, null, null, null, null)).isResumable)
    }
}
