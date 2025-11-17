package com.stash.opusplayer

import android.app.Application

class StashWaveApplication : Application() {
    
    // Shared player manager for the whole app
    val playerManager: com.stash.opusplayer.player.MusicPlayerManager by lazy {
        com.stash.opusplayer.player.MusicPlayerManager(this).apply { initialize() }
    }
    
    override fun onCreate() {
        super.onCreate()
        instance = this
        // Install a simple crash logger to help diagnose startup crashes
        installCrashLogger()
        try {
            com.stash.opusplayer.work.AutoEmbedWorker.schedule(this)
        } catch (_: Exception) {}
    }

    private fun installCrashLogger() {
        val prev = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { t, e ->
            try {
                val dir = java.io.File(cacheDir, "crash_logs").apply { mkdirs() }
                val file = java.io.File(dir, "crash_${System.currentTimeMillis()}.log")
                java.io.PrintWriter(java.io.FileWriter(file)).use { pw ->
                    pw.println("Thread: ${t.name}")
                    e.printStackTrace(pw)
                }
                android.util.Log.e("CrashLogger", "Uncaught exception logged to ${file.absolutePath}", e)
            } catch (_: Exception) {}
            // Delegate to previous handler (will crash app)
            prev?.uncaughtException(t, e) ?: run { android.os.Process.killProcess(android.os.Process.myPid()) }
        }
    }
    
    companion object {
        lateinit var instance: StashWaveApplication
            private set
    }
}
