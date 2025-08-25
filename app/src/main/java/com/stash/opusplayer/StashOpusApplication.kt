package com.stash.opusplayer

import android.app.Application

class StashOpusApplication : Application() {
    
    override fun onCreate() {
        super.onCreate()
        instance = this
    }
    
    companion object {
        lateinit var instance: StashOpusApplication
            private set
    }
}
