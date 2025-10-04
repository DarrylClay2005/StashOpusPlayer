package com.stash.stashwave

import android.app.Application

class StashWaveApplication : Application() {
    
    // Shared player manager for the whole app
    val playerManager: com.stash.stashwave.player.MusicPlayerManager by lazy {
        com.stash.stashwave.player.MusicPlayerManager(this).apply { initialize() }
    }
    
    override fun onCreate() {
        super.onCreate()
        instance = this
        try {
            com.stash.stashwave.work.AutoEmbedWorker.schedule(this)
        } catch (_: Exception) {}
    }
    
    companion object {
        lateinit var instance: StashWaveApplication
            private set
    }
}
