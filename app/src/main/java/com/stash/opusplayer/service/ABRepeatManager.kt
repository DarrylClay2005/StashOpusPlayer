package com.stash.opusplayer.service

import android.content.Context
import android.content.SharedPreferences
import java.security.MessageDigest

/**
 * ABRepeatManager manages A/B loop points per track and a global enable flag.
 *
 * Storage:
 * - Global flag: ab_enabled (boolean)
 * - Per-track points stored using a stable key-derived hash to avoid long keys:
 *   keys: ab_<sha1(key)>_a and ab_<sha1(key)>_b (milliseconds)
 */
class ABRepeatManager(private val context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("ab_repeat", 0)

    fun isEnabled(): Boolean = prefs.getBoolean(KEY_ENABLED, false)

    fun setEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_ENABLED, enabled).apply()
    }

    fun clearAllForTrack(trackKey: String) {
        val h = sha1(trackKey)
        prefs.edit()
            .remove("${KEY_PREFIX}_${h}_a")
            .remove("${KEY_PREFIX}_${h}_b")
            .apply()
    }

    fun setPointA(trackKey: String, positionMs: Long) {
        val h = sha1(trackKey)
        prefs.edit().putLong("${KEY_PREFIX}_${h}_a", positionMs.coerceAtLeast(0L)).apply()
    }

    fun setPointB(trackKey: String, positionMs: Long) {
        val h = sha1(trackKey)
        prefs.edit().putLong("${KEY_PREFIX}_${h}_b", positionMs.coerceAtLeast(0L)).apply()
    }

    fun getPoints(trackKey: String): Pair<Long, Long>? {
        val h = sha1(trackKey)
        val a = prefs.getLong("${KEY_PREFIX}_${h}_a", -1L)
        val b = prefs.getLong("${KEY_PREFIX}_${h}_b", -1L)
        return if (a >= 0 && b >= 0 && b > a) (a to b) else null
    }

    fun hasPoints(trackKey: String): Boolean = getPoints(trackKey) != null

    /**
     * Hook for future enhancements (e.g., per-track defaults). Currently a no-op.
     */
    fun onTrackChanged(trackKey: String) { /* no-op */ }

    private fun sha1(s: String): String {
        return try {
            val md = MessageDigest.getInstance("SHA-1")
            val bytes = md.digest(s.toByteArray(Charsets.UTF_8))
            bytes.joinToString("") { b -> "%02x".format(b) }
        } catch (e: Exception) {
            // Fallback simple hash if SHA-1 unavailable (unlikely)
            Integer.toHexString(s.hashCode())
        }
    }

    companion object {
        private const val KEY_ENABLED = "ab_enabled"
        private const val KEY_PREFIX = "ab"
    }
}
