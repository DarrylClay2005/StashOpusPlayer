package com.stash.opusplayer.music.data.database

import androidx.room.TypeConverter
import org.json.JSONArray

/**
 * Type converters for RevolutionaryMusicDatabase
 */
class MusicTypeConverters {
    
    @TypeConverter
    fun fromStringList(value: List<String>?): String {
        return value?.let { JSONArray(it).toString() } ?: "[]"
    }
    
    @TypeConverter
    fun toStringList(value: String?): List<String> {
        if (value.isNullOrBlank() || value == "[]") return emptyList()
        return try {
            val jsonArray = JSONArray(value)
            List(jsonArray.length()) { i -> jsonArray.getString(i) }
        } catch (e: Exception) {
            emptyList()
        }
    }
    
    @TypeConverter
    fun fromLongList(value: List<Long>?): String {
        return value?.let { JSONArray(it).toString() } ?: "[]"
    }
    
    @TypeConverter
    fun toLongList(value: String?): List<Long> {
        if (value.isNullOrBlank() || value == "[]") return emptyList()
        return try {
            val jsonArray = JSONArray(value)
            List(jsonArray.length()) { i -> jsonArray.getLong(i) }
        } catch (e: Exception) {
            emptyList()
        }
    }
}
