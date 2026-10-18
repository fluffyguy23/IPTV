package com.iptvxtreme.player.core

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull

/**
 * Xtream Codes servers are wildly inconsistent: the same field may be an Int,
 * a quoted String, a Double, or absent. These helpers read leniently so one
 * malformed field never fails the whole response.
 */
fun JsonObject.str(key: String): String? {
    val p = this[key] as? JsonPrimitive ?: return null
    if (p is JsonNull) return null
    return p.content
}

fun JsonObject.int(key: String): Long? {
    val p = this[key] as? JsonPrimitive ?: return null
    if (p is JsonNull) return null
    p.longOrNull?.let { return it }
    p.booleanOrNull?.let { return if (it) 1 else 0 }
    p.doubleOrNull?.let { return it.toLong() }
    val t = p.content.trim()
    return t.toLongOrNull() ?: t.toDoubleOrNull()?.toLong()
}

fun JsonObject.dbl(key: String): Double? {
    val p = this[key] as? JsonPrimitive ?: return null
    if (p is JsonNull) return null
    return p.doubleOrNull ?: p.content.trim().toDoubleOrNull()
}

fun JsonObject.bool(key: String): Boolean? {
    val p = this[key] as? JsonPrimitive ?: return null
    if (p is JsonNull) return null
    p.booleanOrNull?.let { return it }
    p.longOrNull?.let { return it != 0L }
    return when (p.content.lowercase()) {
        "1", "true", "yes" -> true
        "0", "false", "no", "" -> false
        else -> null
    }
}

/** Some endpoints return `[]` when there is no data and a string otherwise. */
fun JsonObject.strList(key: String): List<String>? {
    when (val v = this[key]) {
        is JsonArray -> return v.mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p !is JsonNull }?.content }
        is JsonPrimitive -> if (v !is JsonNull && v.content.isNotEmpty()) return listOf(v.content)
        else -> {}
    }
    return null
}

fun JsonObject.obj(key: String): JsonObject? = this[key] as? JsonObject

fun JsonElement.objects(): List<JsonObject> = (this as? JsonArray)?.mapNotNull { it as? JsonObject } ?: emptyList()

/** Non-empty trimmed string, else null. */
fun String?.nonEmpty(): String? = this?.trim()?.takeIf { it.isNotEmpty() }
