package com.stash.stashwave.integration

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri

/**
 * Integration helper for delegating YouTube URLs to Seal.
 *
 * We try specific known package IDs first, then fall back to any app whose
 * package name or label contains "seal" and can handle the intent.
 *
 * Primary intent is ACTION_SEND with the URL as text (how Seal commonly accepts input),
 * with a secondary fallback to ACTION_VIEW if supported.
 */
object SealIntegration {
    private val KNOWN_PACKAGES = listOf(
        "com.junkfood.seal",
        "com.junkfood.seal.debug",
        "com.junkfood.seal.beta"
    )

    fun isInstalled(context: Context): Boolean {
        val pm = context.packageManager
        // Known packages first
        KNOWN_PACKAGES.forEach { pkg ->
            try {
                pm.getPackageInfo(pkg, 0)
                return true
            } catch (_: Exception) {}
        }
        // Fallback: look for apps that can handle sharing/viewing and look like Seal
        return try {
            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
            }
            val matches = pm.queryIntentActivities(shareIntent, 0)
            matches.any {
                val pkg = it.activityInfo?.packageName ?: ""
                val label = it.loadLabel(pm)?.toString() ?: ""
                pkg.contains("seal", ignoreCase = true) || label.contains("seal", ignoreCase = true)
            }
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Open the given YouTube URL directly in Seal. Returns true if an intent
     * could be launched, false otherwise.
     */
    fun openInSeal(context: Context, youtubeUrl: String): Boolean {
        val pm = context.packageManager
        // Prefer ACTION_SEND (most reliable for download apps)
        val shareIntentBase = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, youtubeUrl)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        // Try known packages explicitly
        KNOWN_PACKAGES.forEach { pkg ->
            try {
                pm.getPackageInfo(pkg, 0)
                val intent = Intent(shareIntentBase).apply { `package` = pkg }
                context.startActivity(intent)
                return true
            } catch (_: Exception) {}
        }

        // Try any app that looks like Seal and can handle share
        try {
            val matches = pm.queryIntentActivities(shareIntentBase, 0)
            val sealMatch = matches.firstOrNull {
                val pkg = it.activityInfo?.packageName ?: ""
                val label = it.loadLabel(pm)?.toString() ?: ""
                pkg.contains("com.junkfood.seal", ignoreCase = true) ||
                pkg.contains("seal", ignoreCase = true) ||
                label.contains("seal", ignoreCase = true)
            }
            if (sealMatch != null) {
                val intent = Intent(shareIntentBase).apply { `package` = sealMatch.activityInfo.packageName }
                context.startActivity(intent)
                return true
            }
        } catch (_: Exception) {}

        // Fallback: try ACTION_VIEW with the URL (in case Seal exposes a view filter)
        return try {
            val viewIntent = Intent(Intent.ACTION_VIEW, Uri.parse(youtubeUrl)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val matches = pm.queryIntentActivities(viewIntent, 0)
            val sealMatch = matches.firstOrNull {
                val pkg = it.activityInfo?.packageName ?: ""
                val label = it.loadLabel(pm)?.toString() ?: ""
                pkg.contains("com.junkfood.seal", ignoreCase = true) ||
                pkg.contains("seal", ignoreCase = true) ||
                label.contains("seal", ignoreCase = true)
            }
            if (sealMatch != null) {
                viewIntent.`package` = sealMatch.activityInfo.packageName
                context.startActivity(viewIntent)
                true
            } else {
                false
            }
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Prompt installation by opening the project page (GitHub) or F-Droid.
     */
    fun promptInstall(context: Context) {
        val urls = listOf(
            // F-Droid package page (if present)
            "https://f-droid.org/packages/com.junkfood.seal/",
            // GitHub project page
            "https://github.com/JunkFood02/Seal"
        )
        for (u in urls) {
            try {
                context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(u)).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                })
                return
            } catch (_: Exception) {
                // try next
            }
        }
    }
}