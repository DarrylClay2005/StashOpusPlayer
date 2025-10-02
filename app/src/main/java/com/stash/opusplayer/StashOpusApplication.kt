package com.stash.stashwave

import android.app.Application

class StashWaveApplication : Application() {
    
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
