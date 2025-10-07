package com.stash.opusplayer.utils

import android.content.Context
import android.net.Uri
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.security.MessageDigest

/**
 * Lightweight ReplayGain parser using jaudiotagger.
 * - Parses common tags: REPLAYGAIN_TRACK_GAIN/ALBUM_GAIN, REPLAYGAIN_TRACK_PEAK/ALBUM_PEAK
 * - Best-effort parsing of R128_*_GAIN (various units encountered in wild)
 * - Works with file paths and content URIs (by copying to a temp file)
 */
object ReplayGainUtil {
    data class Info(
        val trackGainDb: Float?,
        val albumGainDb: Float?,
        val trackPeak: Float?,
        val albumPeak: Float?
    )

    private data class CacheEntry(
        val info: Info,
        val lastModified: Long, // -1 if unknown
        val savedAt: Long
    )

    private const val TAG = "ReplayGainUtil"
    private const val MAX_MEM_CACHE = 128
    private const val MAX_DISK_CACHE = 200
    private const val DISK_TTL_MS = 7L * 24L * 60L * 60L * 1000L // 7 days

    // Simple LRU mem cache
    private val memCache = object : LinkedHashMap<String, CacheEntry>(MAX_MEM_CACHE, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, CacheEntry>?): Boolean {
            return size > MAX_MEM_CACHE
        }
    }

    fun parseWithCache(context: Context, uriOrPath: String): Info? {
        val key = buildKey(uriOrPath)
        val now = System.currentTimeMillis()
        val lm = currentLastModified(context, uriOrPath)

        // In-memory
        synchronized(memCache) {
            memCache[key]?.let { e ->
                if (isValid(e, lm, now)) return e.info
            }
        }
        // Disk
        loadFromDisk(context, key)?.let { e ->
            if (isValid(e, lm, now)) {
                synchronized(memCache) { memCache[key] = e }
                return e.info
            }
        }
        // Parse and cache
        val parsed = parseInternal(context, uriOrPath) ?: return null
        val entry = CacheEntry(parsed, lm, now)
        synchronized(memCache) { memCache[key] = entry }
        saveToDisk(context, key, entry)
        trimDisk(context)
        return parsed
    }

    fun parse(context: Context, uriOrPath: String): Info? = parseInternal(context, uriOrPath)

    private fun parseInternal(context: Context, uriOrPath: String): Info? {
        return try {
            val file = resolveToTempFileIfNeeded(context, uriOrPath) ?: return null
            val audioFile = org.jaudiotagger.audio.AudioFileIO.read(file)
            val tag = audioFile.tag

            var trackGain: Float? = null
            var albumGain: Float? = null
            var trackPeak: Float? = null
            var albumPeak: Float? = null

            if (tag != null) {
                // Common ReplayGain
                trackGain = parseDb(tag.getFirst("REPLAYGAIN_TRACK_GAIN")) ?: trackGain
                albumGain = parseDb(tag.getFirst("REPLAYGAIN_ALBUM_GAIN")) ?: albumGain
                trackPeak = parsePeak(tag.getFirst("REPLAYGAIN_TRACK_PEAK")) ?: trackPeak
                albumPeak = parsePeak(tag.getFirst("REPLAYGAIN_ALBUM_PEAK")) ?: albumPeak

                // Some files store in TXXX frames (jaudiotagger normalizes many cases already)
                if (trackGain == null) trackGain = parseDb(tag.getFirst("TXXX:REPLAYGAIN_TRACK_GAIN"))
                if (albumGain == null) albumGain = parseDb(tag.getFirst("TXXX:REPLAYGAIN_ALBUM_GAIN"))
                if (trackPeak == null) trackPeak = parsePeak(tag.getFirst("TXXX:REPLAYGAIN_TRACK_PEAK"))
                if (albumPeak == null) albumPeak = parsePeak(tag.getFirst("TXXX:REPLAYGAIN_ALBUM_PEAK"))

                // R128 tags (best-effort; various units observed). Heuristics keep within +/- 30 dB.
                if (trackGain == null) trackGain = normalizeR128(tag.getFirst("R128_TRACK_GAIN"))
                if (albumGain == null) albumGain = normalizeR128(tag.getFirst("R128_ALBUM_GAIN"))
            }

            Info(trackGain, albumGain, trackPeak, albumPeak)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse ReplayGain", e)
            null
        }
    }

    private fun buildKey(uriOrPath: String): String {
        return if (uriOrPath.startsWith("content://")) {
            "uri:" + uriOrPath
        } else {
            try {
                val f = File(uriOrPath)
                "file:" + f.absolutePath.lowercase()
            } catch (_: Exception) {
                "file:" + uriOrPath.lowercase()
            }
        }
    }

    private fun currentLastModified(context: Context, uriOrPath: String): Long {
        return try {
            if (!uriOrPath.startsWith("content://")) {
                val f = File(uriOrPath)
                if (f.exists()) f.lastModified() else -1L
            } else {
                // For content URIs, we don't have a reliable last-modified; use -1 and rely on TTL
                -1L
            }
        } catch (_: Exception) { -1L }
    }

    private fun isValid(entry: CacheEntry, currentLm: Long, now: Long): Boolean {
        return if (entry.lastModified >= 0 && currentLm >= 0) {
            // For file paths, require matching lastModified
            entry.lastModified == currentLm
        } else {
            // For content URIs, use TTL
            now - entry.savedAt <= DISK_TTL_MS
        }
    }

    private fun prefs(context: Context): android.content.SharedPreferences {
        return context.getSharedPreferences("replaygain_cache", 0)
    }

    private fun loadFromDisk(context: Context, key: String): CacheEntry? {
        return try {
            val p = prefs(context)
            val kh = sha1(key)
            val json = p.getString("entry_$kh", null) ?: return null
            val obj = org.json.JSONObject(json)
            val info = Info(
                trackGainDb = obj.optDouble("tg", Double.NaN).let { if (it.isNaN()) null else it.toFloat() },
                albumGainDb = obj.optDouble("ag", Double.NaN).let { if (it.isNaN()) null else it.toFloat() },
                trackPeak = obj.optDouble("tp", Double.NaN).let { if (it.isNaN()) null else it.toFloat() },
                albumPeak = obj.optDouble("ap", Double.NaN).let { if (it.isNaN()) null else it.toFloat() }
            )
            val lm = obj.optLong("lm", -1L)
            val sa = obj.optLong("sa", 0L)
            CacheEntry(info, lm, sa)
        } catch (_: Exception) { null }
    }

    private fun saveToDisk(context: Context, key: String, entry: CacheEntry) {
        try {
            val p = prefs(context)
            val ed = p.edit()
            val kh = sha1(key)
            val obj = org.json.JSONObject().apply {
                put("tg", entry.info.trackGainDb ?: org.json.JSONObject.NULL)
                put("ag", entry.info.albumGainDb ?: org.json.JSONObject.NULL)
                put("tp", entry.info.trackPeak ?: org.json.JSONObject.NULL)
                put("ap", entry.info.albumPeak ?: org.json.JSONObject.NULL)
                put("lm", entry.lastModified)
                put("sa", entry.savedAt)
            }
            ed.putString("entry_$kh", obj.toString())
            // Maintain order for LRU trimming
            val idxKey = "index"
            val current = p.getString(idxKey, null)?.let { org.json.JSONArray(it) } ?: org.json.JSONArray()
            // Remove if already present
            val list = mutableListOf<String>()
            for (i in 0 until current.length()) list.add(current.getString(i))
            list.remove(kh)
            list.add(kh)
            // Trim
            while (list.size > MAX_DISK_CACHE) list.removeAt(0)
            val arr = org.json.JSONArray()
            list.forEach { arr.put(it) }
            ed.putString(idxKey, arr.toString())
            ed.apply()
        } catch (_: Exception) {}
    }

    private fun trimDisk(context: Context) {
        try {
            val p = prefs(context)
            val idxKey = "index"
            val arr = p.getString(idxKey, null)?.let { org.json.JSONArray(it) } ?: return
            val list = mutableListOf<String>()
            for (i in 0 until arr.length()) list.add(arr.getString(i))
            if (list.size <= MAX_DISK_CACHE) return
            val ed = p.edit()
            while (list.size > MAX_DISK_CACHE) {
                val oldest = list.removeAt(0)
                ed.remove("entry_$oldest")
            }
            val newArr = org.json.JSONArray()
            list.forEach { newArr.put(it) }
            ed.putString(idxKey, newArr.toString()).apply()
        } catch (_: Exception) {}
    }

    private fun parseDb(value: String?): Float? {
        if (value.isNullOrBlank()) return null
        // Accept forms like "-7.12 dB" or "-7.12"
        val cleaned = value.lowercase().replace("db", "").trim()
        return cleaned.toFloatOrNull()?.coerceIn(-30f, 30f)
    }

    private fun parsePeak(value: String?): Float? {
        if (value.isNullOrBlank()) return null
        // Peaks are usually linear [0..1], but sometimes stored as strings
        return value.trim().toFloatOrNull()?.takeIf { it > 0f }
    }

    private fun normalizeR128(value: String?): Float? {
        if (value.isNullOrBlank()) return null
        val raw = value.trim()
        val n = raw.toFloatOrNull()
        if (n != null) {
            // Heuristics:
            // - If |n| <= 60 -> assume already in dB
            // - If 60 < |n| <= 600 -> divide by 10
            // - If 600 < |n| <= 6000 -> divide by 100
            // - Else -> divide by 256 (common for some tools)
            val abs = kotlin.math.abs(n)
            val db = when {
                abs <= 60f -> n
                abs <= 600f -> n / 10f
                abs <= 6000f -> n / 100f
                else -> n / 256f
            }
            return db.coerceIn(-30f, 30f)
        }
        // Sometimes like "-7.12 dB" format; reuse parseDb
        return parseDb(raw)
    }

    private fun resolveToTempFileIfNeeded(context: Context, uriOrPath: String): File? {
        return try {
            if (!uriOrPath.startsWith("content://")) {
                val f = File(uriOrPath)
                return if (f.exists()) f else null
            }
            // Copy content URI to cache for tag reading
            val uri = Uri.parse(uriOrPath)
            val cacheDir = File(context.cacheDir, "rg_cache").apply { mkdirs() }
            val name = sha1(uriOrPath)
            val out = File(cacheDir, "$name.bin")
            if (out.exists() && out.length() > 0L) return out
            context.contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(out).use { output ->
                    input.copyTo(output, 64 * 1024)
                }
            } ?: return null
            out
        } catch (_: Exception) { null }
    }

    private fun sha1(s: String): String {
        val md = MessageDigest.getInstance("SHA-1")
        val bytes = md.digest(s.toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { b -> "%02x".format(b) }
    }
}
