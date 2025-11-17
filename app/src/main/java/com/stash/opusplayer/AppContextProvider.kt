package com.stash.opusplayer

import android.app.Application
import android.content.Context

/**
 * Provides application context for non-Android entry points
 */
object AppContextProvider {
    private lateinit var application: Application
    
    fun init(app: Application) {
        application = app
    }
    
    fun getContext(): Context = application.applicationContext
    
    fun getApplication(): Application = application
}
