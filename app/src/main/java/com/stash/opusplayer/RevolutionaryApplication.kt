package com.stash.opusplayer

import android.app.Application
import androidx.work.Configuration
import timber.log.Timber

/**
 * Revolutionary Application - Complete application with all features
 */
class RevolutionaryApplication : Application(), Configuration.Provider {
    
    // Shared player manager for the whole app (merged from StashWaveApplication)
    val playerManager: com.stash.opusplayer.player.MusicPlayerManager by lazy {
        com.stash.opusplayer.player.MusicPlayerManager(this).apply { initialize() }
    }
    
    override fun onCreate() {
        super.onCreate()
        instance = this
        
        // Install crash logger (merged from StashWaveApplication)
        installCrashLogger()
        
        try {
            // Initialize Timber for logging
            if (BuildConfig.DEBUG) {
                Timber.plant(Timber.DebugTree())
            }
        } catch (e: Exception) {
            android.util.Log.e("RevApp", "Failed to init Timber", e)
        }

        // Initialize AWS Amplify plugins (Auth + Storage + API)
        try {
            com.amplifyframework.core.Amplify.addPlugin(
                com.amplifyframework.auth.cognito.AWSCognitoAuthPlugin()
            )
            try {
                com.amplifyframework.core.Amplify.addPlugin(
                    com.amplifyframework.api.aws.AWSApiPlugin()
                )
            } catch (_: Exception) { Timber.w("AWSApiPlugin not configured; skipping") }
            try {
                com.amplifyframework.core.Amplify.addPlugin(
                    com.amplifyframework.storage.s3.AWSS3StoragePlugin()
                )
            } catch (_: Exception) { Timber.w("AWSS3StoragePlugin not configured; skipping") }
            com.amplifyframework.core.Amplify.configure(applicationContext)
            Timber.i("Amplify initialized")
        } catch (e: Exception) {
            Timber.e(e, "Failed to initialize Amplify")
        }
        // Start cloud syncs (settings + favorites) once auth is available
        try {
            com.amplifyframework.core.Amplify.Auth.fetchAuthSession({ session ->
                if (session.isSignedIn) {
                    // Settings sync
                    com.stash.opusplayer.cloud.CloudSettingsRepository.startSync(this)
                    // Favorites initial pull (best-effort)
                    kotlinx.coroutines.GlobalScope.launch(kotlinx.coroutines.Dispatchers.IO) {
                        try {
                            val db = com.stash.opusplayer.data.database.MusicDatabase.getDatabase(this@RevolutionaryApplication)
                            com.stash.opusplayer.cloud.CloudFavoritesRepository.pullFavoritesToLocal(this@RevolutionaryApplication, db.favoriteDao())
                        } catch (_: Exception) {}
                    }
                }
            }, { _: Exception -> })
        } catch (_: Exception) {}
        
        try {
            Timber.i("🚀 Revolutionary Stash Opus Player initialized")
            
            // Provide application context for non-Android entry points (Compose VM scheduling)
            try {
                AppContextProvider.init(this)
                Timber.d("AppContextProvider initialized successfully")
            } catch (e: Exception) {
                Timber.e(e, "Failed to initialize AppContextProvider")
            }
            
            // Nightly metadata backup to app-specific storage
            try {
                val outDir = getExternalFilesDir("backups") ?: filesDir
                val outPath = java.io.File(outDir, "metadata_backup.json").absolutePath
                com.stash.opusplayer.work.MetadataBackupWorker.scheduleNightlyBackup(this, outPath)
                Timber.d("Metadata backup worker scheduled successfully")
            } catch (e: Exception) {
                Timber.e(e, "Failed to schedule metadata backup worker")
            }
            
            Timber.i("✅ Revolutionary Stash Opus Player initialization complete")
            
            // Schedule auto-embed worker (merged from StashWaveApplication)
            try {
                com.stash.opusplayer.work.AutoEmbedWorker.schedule(this)
            } catch (_: Exception) {}
            
        } catch (e: Exception) {
            // Catch any unexpected initialization errors
            Timber.e(e, "❌ Fatal error during application initialization")
            // Don't rethrow - allow app to try to start anyway
        }
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
    
    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .build()
    
    companion object {
        lateinit var instance: RevolutionaryApplication
            private set
    }
}
