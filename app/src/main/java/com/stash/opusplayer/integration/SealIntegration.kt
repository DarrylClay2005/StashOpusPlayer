package com.stash.opusplayer.integration

import android.content.ActivityNotFoundException
import android.content.ClipData
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
     * Enhanced hand-off that supplies a desired download location (URI or filesystem path)
     * and a suggested filename to Seal via Intent extras and temporary URI permissions.
     *
     * Note: Seal may ignore these hints depending on its version. We pass multiple
     * common extra keys to maximize compatibility.
     */
    fun openInSealWithLocation(
        context: Context,
        youtubeUrl: String,
        downloadUriOrPath: String?,
        suggestedFileName: String? = null
    ): Boolean {
        val pm = context.packageManager

        val shareIntentBase = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, youtubeUrl)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        // Attach location hints when provided
        val (clipUri, pathString) = when {
            downloadUriOrPath.isNullOrBlank() -> null to null
            downloadUriOrPath.startsWith("content://") -> Uri.parse(downloadUriOrPath) to null
            else -> null to downloadUriOrPath
        }

        if (clipUri != null) {
            // Grant temporary read/write access to the selected folder URI
            shareIntentBase.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            shareIntentBase.clipData = ClipData.newUri(context.contentResolver, "download_dir", clipUri)
            // Provide several potential extra keys that Seal could support
            shareIntentBase.putExtra("com.junkfood.seal.EXTRA_SAVE_DIR_URI", clipUri)
            shareIntentBase.putExtra("com.junkfood.seal.EXTRA_DOWNLOAD_DIR_URI", clipUri)
            shareIntentBase.putExtra("com.junkfood.seal.EXTRA_OUTPUT_DIR_URI", clipUri)
            shareIntentBase.putExtra(Intent.EXTRA_STREAM, clipUri) // as a hint
        }
        if (!pathString.isNullOrBlank()) {
            shareIntentBase.putExtra("com.junkfood.seal.EXTRA_SAVE_DIR", pathString)
            shareIntentBase.putExtra("com.junkfood.seal.EXTRA_DOWNLOAD_DIR", pathString)
            shareIntentBase.putExtra("com.junkfood.seal.EXTRA_OUTPUT_DIR", pathString)
            shareIntentBase.putExtra("save_dir", pathString)
            shareIntentBase.putExtra("download_dir", pathString)
            shareIntentBase.putExtra("output_dir", pathString)
        }
        suggestedFileName?.let { name ->
            shareIntentBase.putExtra("com.junkfood.seal.EXTRA_FILE_NAME", name)
            shareIntentBase.putExtra("file_name", name)
            shareIntentBase.putExtra("filename", name)
        }

        // Try known packages explicitly first
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

        // Fallback to ACTION_VIEW (less likely to honor extras)
        return try {
            val viewIntent = Intent(Intent.ACTION_VIEW, Uri.parse(youtubeUrl)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            if (clipUri != null) {
                viewIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                viewIntent.clipData = ClipData.newUri(context.contentResolver, "download_dir", clipUri)
            }
            suggestedFileName?.let { name -> viewIntent.putExtra("filename", name) }
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
