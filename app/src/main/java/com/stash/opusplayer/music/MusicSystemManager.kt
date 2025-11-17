package com.stash.opusplayer.music

import android.content.Context
import com.stash.opusplayer.music.data.database.RevolutionaryMusicDatabase
import com.stash.opusplayer.music.data.repository.RevolutionaryMusicRepositoryImpl
import com.stash.opusplayer.music.domain.repository.MusicRepository
import com.stash.opusplayer.music.library.RevolutionaryLibraryManager
import com.stash.opusplayer.music.scanner.RevolutionaryMusicScanner
import com.stash.opusplayer.playback.RevolutionaryPlaybackEngine

/**
 * Music System Manager
 * 
 * Central integration point for all music systems:
 * - Database
 * - Repository
 * - Library Manager
 * - Scanner
 * - Playback Engine
 * 
 * Provides singleton access and lifecycle management
 */
class MusicSystemManager private constructor(context: Context) {
    
    companion object {
        @Volatile
        private var INSTANCE: MusicSystemManager? = null
        
        fun getInstance(context: Context): MusicSystemManager {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: MusicSystemManager(context.applicationContext).also {
                    INSTANCE = it
                }
            }
        }
    }
    
    private val appContext = context.applicationContext
    
    // Core systems
    val database: RevolutionaryMusicDatabase by lazy {
        RevolutionaryMusicDatabase.getDatabase(appContext)
    }
    
    val repository: MusicRepository by lazy {
        RevolutionaryMusicRepositoryImpl(database)
    }
    
    val libraryManager: RevolutionaryLibraryManager by lazy {
        RevolutionaryLibraryManager(appContext, repository)
    }
    
    val scanner: RevolutionaryMusicScanner by lazy {
        RevolutionaryMusicScanner(appContext, repository)
    }
    
    val playbackEngine: RevolutionaryPlaybackEngine by lazy {
        RevolutionaryPlaybackEngine(appContext, repository)
    }
    
    /**
     * Clean up all systems
     * Should be called when app is shutting down
     */
    fun cleanup() {
        libraryManager.cleanup()
        scanner.cleanup()
        playbackEngine.cleanup()
    }
    
    /**
     * Initialize all systems
     * Call this early in app lifecycle
     */
    suspend fun initialize() {
        // Pre-load critical systems
        database
        repository
        libraryManager
        
        // Refresh collections
        libraryManager.refreshCollections()
    }
}
