package com.stash.opusplayer.cloud

import android.content.Context
import android.content.SharedPreferences
import androidx.preference.PreferenceManager
import com.amplifyframework.core.Amplify
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject
import timber.log.Timber
import java.io.File

/**
 * Syncs app settings to Amplify S3 per-user as JSON (users/{uid}/settings.json).
 * Uses local SharedPreferences as cache; cloud is source of truth when available.
 */
object CloudSettingsRepository {
    private val ioScope = CoroutineScope(Dispatchers.IO)
    private var listener: SharedPreferences.OnSharedPreferenceChangeListener? = null
    private val mutex = Mutex()
    private var debounceJob: Job? = null

    private fun settingsPrefs(ctx: Context): SharedPreferences = ctx.getSharedPreferences("settings", 0)

    fun startSync(context: Context) {
        // Download and apply cloud settings once
        ioScope.launch { pullFromCloudAndApply(context) }
        // Register listener to push on changes
        try {
            val prefs = settingsPrefs(context)
            if (listener != null) return
            listener = SharedPreferences.OnSharedPreferenceChangeListener { _, _ ->
                debounceJob?.cancel()
                debounceJob = ioScope.launch {
                    kotlinx.coroutines.delay(800)
                    pushToCloud(context)
                }
            }
            prefs.registerOnSharedPreferenceChangeListener(listener)
        } catch (e: Exception) {
            Timber.w(e, "Failed to register cloud settings sync listener")
        }
    }

    suspend fun pullFromCloudAndApply(context: Context) {
        mutex.withLock {
            val userId = runCatching { Amplify.Auth.currentUser.userId }.getOrNull() ?: return
            val key = "users/$userId/settings.json"
            val tmp = File.createTempFile("cloud_settings_", ".json", context.cacheDir)
            try {
                val result = kotlinx.coroutines.suspendCancellableCoroutine<Boolean> { cont ->
                    Amplify.Storage.downloadFile(key, tmp, { _ -> cont.resume(true) {} }, { err ->
                        Timber.i(err, "No cloud settings yet; skipping pull")
                        cont.resume(false) {}
                    })
                }
                if (result) {
                    val text = tmp.readText()
                    applySettingsJson(context, text)
                }
            } catch (e: Exception) {
                Timber.w(e, "pullFromCloud failed")
            } finally { runCatching { tmp.delete() } }
        }
    }

    private fun applySettingsJson(context: Context, jsonText: String) {
        try {
            val json = JSONObject(jsonText)
            val prefs = settingsPrefs(context).edit()
            for (key in json.keys()) {
                when (val v = json.get(key)) {
                    is Boolean -> prefs.putBoolean(key, v)
                    is Int -> prefs.putInt(key, v)
                    is Long -> prefs.putLong(key, v)
                    is Double -> prefs.putFloat(key, v.toFloat())
                    is String -> prefs.putString(key, v)
                }
            }
            prefs.apply()
        } catch (e: Exception) {
            Timber.w(e, "Failed to apply cloud settings json")
        }
    }

    suspend fun pushToCloud(context: Context) {
        mutex.withLock {
            val userId = runCatching { Amplify.Auth.currentUser.userId }.getOrNull() ?: return
            val key = "users/$userId/settings.json"
            val tmp = File.createTempFile("cloud_settings_push_", ".json", context.cacheDir)
            try {
                val json = exportSettingsJson(context)
                tmp.writeText(json.toString())
                val result = kotlinx.coroutines.suspendCancellableCoroutine<Boolean> { cont ->
                    Amplify.Storage.uploadFile(key, tmp, { _ -> cont.resume(true) {} }, { err ->
                        Timber.w(err, "pushToCloud failed")
                        cont.resume(false) {}
                    })
                }
                if (result) Timber.i("Settings pushed to cloud")
            } catch (e: Exception) {
                Timber.w(e, "pushToCloud error")
            } finally { runCatching { tmp.delete() } }
        }
    }

    private fun exportSettingsJson(context: Context): JSONObject {
        val prefs = settingsPrefs(context).all
        val json = JSONObject()
        prefs.forEach { (k, v) ->
            when (v) {
                is Boolean, is Int, is Long, is Float, is String -> json.put(k, v)
                is Set<*> -> json.put(k, (v as Set<*>).joinToString("|"))
            }
        }
        // Also include a small subset of PreferenceManager defaults if needed
        val defaultPrefs = PreferenceManager.getDefaultSharedPreferences(context).all
        defaultPrefs.forEach { (k, v) ->
            if (!json.has(k)) {
                when (v) {
                    is Boolean, is Int, is Long, is Float, is String -> json.put(k, v)
                }
            }
        }
        return json
    }
}
