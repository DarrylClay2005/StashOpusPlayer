package com.stash.opusplayer.utils

object YouTubeCommentsCache {
    private data class Key(val videoId: String, val order: String)
data class Entry(val comments: List<com.stash.opusplayer.data.YouTubeComment>, val nextPageToken: String?)

    private val maxEntries = 32
    private val map = object : LinkedHashMap<Key, Entry>(maxEntries, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<Key, Entry>?): Boolean {
            return size > maxEntries
        }
    }

    fun get(videoId: String, order: String): Entry? = synchronized(map) { map[Key(videoId, order)] }
    fun put(videoId: String, order: String, entry: Entry) = synchronized(map) { map[Key(videoId, order)] = entry }
}
