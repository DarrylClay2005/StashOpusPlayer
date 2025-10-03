package com.stash.stashwave.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat as MediaNotificationCompat
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.common.PlaybackParameters
import android.media.audiofx.PresetReverb
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import androidx.media3.session.MediaSessionService
import com.stash.stashwave.R
import androidx.preference.PreferenceManager
import com.stash.stashwave.audio.EqualizerManager
import com.stash.stashwave.data.Song
import com.stash.stashwave.ui.MainActivity
import kotlin.math.pow

class MusicService : MediaSessionService() {
    
    companion object {
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "music_playback"
    }
    
    private var mediaSession: MediaSession? = null
private lateinit var activePlayer: ExoPlayer
    private var sparePlayer: ExoPlayer? = null
    private var isCrossfading: Boolean = false
    private var crossfadeCheckRunnable: Runnable? = null
    private lateinit var equalizerManager: EqualizerManager
    private var presetReverb: PresetReverb? = null
    private var lastAudioSessionId: Int = C.AUDIO_SESSION_ID_UNSET
    private var currentSpeed: Float = 1.0f
    private var currentPitch: Float = 1.0f
    private var currentReverb: Short = 0
    private lateinit var notificationManager: NotificationManager
    private var appInForeground = true
    private var stopServiceWhenPaused = false

    // Phase 2: App volume and crossfade controls
    // Store UI-domain volume [0..1]; map to amplitude using a perceptual curve when applying to ExoPlayer
    private var appVolumeUi: Float = 1.0f
    private val volumeGamma: Float = 2.0f
    private fun uiToAmp(v: Float): Float = v.coerceIn(0f, 1f).pow(volumeGamma)
    private var crossfadeEnabled: Boolean = false
    private var crossfadeDurationMs: Long = 1000L
    private var audioFocusEnabled: Boolean = true

    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private var fadeRunnable: Runnable? = null

    private var audioAttributes: AudioAttributes = AudioAttributes.Builder()
        .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
        .setUsage(C.USAGE_MEDIA)
        .build()
    
    override fun onCreate() {
        super.onCreate()
        
        notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        createNotificationChannel()
        
        // Register preference listeners so audio settings persist and apply instantly
        registerPreferenceListeners()
        
        initializePlayers()
        initializeEqualizer()
        initializeMediaSession()
        setupPlayerListener()
    }
    
private fun initializePlayers() {
        // Configure a custom HTTP data source with a modern mobile user-agent for broader CDN compatibility
        val httpFactory = androidx.media3.datasource.DefaultHttpDataSource.Factory()
            .setUserAgent("Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36 StashAudio/8.1.6")
            .setAllowCrossProtocolRedirects(true)
        // Wrap http factory with DefaultDataSource so local file/content URIs continue to work
        val defaultDsFactory = androidx.media3.datasource.DefaultDataSource.Factory(this, httpFactory)
        val mediaSourceFactory = androidx.media3.exoplayer.source.DefaultMediaSourceFactory(defaultDsFactory)

activePlayer = ExoPlayer.Builder(this)
            .setMediaSourceFactory(mediaSourceFactory)
            .build()

        // Prepare spare player for experimental crossfade
        sparePlayer = ExoPlayer.Builder(this)
            .setMediaSourceFactory(mediaSourceFactory)
            .build()
        try { sparePlayer?.setAudioAttributes(audioAttributes, audioFocusEnabled) } catch (_: Exception) {}
        try { sparePlayer?.setHandleAudioBecomingNoisy(true) } catch (_: Exception) {}
        try { sparePlayer?.volume = 0f } catch (_: Exception) {}

        // Read persisted phase-2 audio preferences
        try {
            val prefs = getSharedPreferences("settings", 0)
            audioFocusEnabled = prefs.getBoolean("audio_focus_enabled", true)
            appVolumeUi = prefs.getFloat("app_volume", 1.0f).coerceIn(0f, 1f)
            crossfadeEnabled = prefs.getBoolean("crossfade_enabled", false)
            crossfadeDurationMs = prefs.getLong("crossfade_duration_ms", 1000L).coerceIn(0L, 5000L)
        } catch (_: Exception) {}

        // Apply audio attributes with focus handling preference
try { activePlayer.setAudioAttributes(audioAttributes, audioFocusEnabled) } catch (_: Exception) {}
        try { activePlayer.setHandleAudioBecomingNoisy(true) } catch (_: Exception) {}
        try { activePlayer.volume = uiToAmp(appVolumeUi) } catch (_: Exception) {}

        // Apply persisted playback parameters (speed/pitch/reverb) and playback modes if available
        try {
            val prefs = getSharedPreferences("settings", 0)
            val savedSemitones = prefs.getInt("pitch_semitones", 0)
            currentPitch = Math.pow(2.0, savedSemitones / 12.0).toFloat()
            val savedSpeed = prefs.getFloat("playback_speed", 1.0f)
            if (savedSpeed in 0.25f..2.5f) currentSpeed = savedSpeed
            currentReverb = prefs.getInt("reverb_preset", 0).toShort()
activePlayer.playbackParameters = PlaybackParameters(currentSpeed, currentPitch)
            // Apply shuffle and repeat mode
val savedShuffle = prefs.getBoolean("playback_shuffle", false)
            val savedRepeat = prefs.getInt("playback_repeat_mode", Player.REPEAT_MODE_OFF)
            activePlayer.shuffleModeEnabled = savedShuffle
            activePlayer.repeatMode = savedRepeat
        } catch (_: Exception) { /* ignore */ }
    }
    
    private fun initializeMediaSession() {
        val sessionActivityPendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val callback = object : MediaSession.Callback {
            override fun onCustomCommand(
                session: MediaSession,
                controller: MediaSession.ControllerInfo,
                customCommand: SessionCommand,
                args: android.os.Bundle
            ): com.google.common.util.concurrent.ListenableFuture<SessionResult> {
                try {
                    when (customCommand.customAction) {
                        "SET_EQ_ENABLED" -> {
                            val enabled = args.getBoolean("enabled", false)
                            equalizerManager.setEnabled(enabled)
                            // Persist to default prefs so state survives and listeners react
                            PreferenceManager.getDefaultSharedPreferences(this@MusicService).edit()
                                .putBoolean("equalizer_enabled", enabled)
                                .apply()
                        }
                        "SET_EQ_PRESET" -> {
                            val name = args.getString("preset") ?: "NORMAL"
                            try {
equalizerManager.setPreset(com.stash.stashwave.audio.EqualizerPreset.valueOf(name))
                                // Ensure effects are enabled when user selects a preset
                                equalizerManager.setEnabled(true)
                                // Persist in both default prefs and settings
                                PreferenceManager.getDefaultSharedPreferences(this@MusicService).edit()
                                    .putBoolean("equalizer_enabled", true)
                                    .apply()
                                getSharedPreferences("settings", 0).edit()
                                    .putBoolean("equalizer_enabled", true)
                                    .apply()
                            } catch (_: Exception) {}
                        }
                        "SET_EQ_BAND" -> {
                            val band = args.getInt("band", 0)
                            val level = args.getFloat("level", 0f)
                            equalizerManager.setBandLevel(band, level)
                            // Auto-enable to ensure audible effect
                            equalizerManager.setEnabled(true)
                            PreferenceManager.getDefaultSharedPreferences(this@MusicService).edit()
                                .putBoolean("equalizer_enabled", true)
                                .apply()
                            getSharedPreferences("settings", 0).edit()
                                .putBoolean("equalizer_enabled", true)
                                .apply()
                        }
                        "SET_BASS_BOOST" -> {
                            val strength = args.getInt("strength", 0)
                            equalizerManager.setBassBoost(strength)
                            // Auto-enable to ensure audible effect
                            equalizerManager.setEnabled(true)
                            // Persist in both default prefs and settings
                            PreferenceManager.getDefaultSharedPreferences(this@MusicService).edit()
                                .putBoolean("equalizer_enabled", true)
                                .apply()
                            getSharedPreferences("settings", 0).edit()
                                .putBoolean("equalizer_enabled", true)
                                .apply()
                        }
                        "SET_VIRTUALIZER" -> {
                            val strength = args.getInt("strength", 0)
                            equalizerManager.setVirtualizer(strength)
                            // Auto-enable to ensure audible effect
                            equalizerManager.setEnabled(true)
                            // Persist in both default prefs and settings
                            PreferenceManager.getDefaultSharedPreferences(this@MusicService).edit()
                                .putBoolean("equalizer_enabled", true)
                                .apply()
                            getSharedPreferences("settings", 0).edit()
                                .putBoolean("equalizer_enabled", true)
                                .apply()
                        }
                        "SET_SPEED" -> {
                            val speed = args.getFloat("speed", 1f)
                            setPlaybackSpeed(speed)
                        }
                        "SET_PITCH" -> {
                            val pitch = args.getFloat("pitch", 1f)
                            setPlaybackPitch(pitch)
                        }
                        "SET_REVERB" -> {
                            val preset = args.getInt("preset", 0).toShort()
                            setReverbPreset(preset)
                        }
                        // Phase 2 additions
                        "SET_APP_VOLUME" -> {
                            val vol = args.getFloat("volume", 1f)
                            setAppVolume(vol)
                        }
                        "SET_CROSSFADE_ENABLED" -> {
                            val enabled = args.getBoolean("enabled", false)
                            setCrossfadeEnabled(enabled)
                        }
                        "SET_CROSSFADE_DURATION" -> {
                            val durMs = args.getLong("duration_ms", 1000L)
                            setCrossfadeDuration(durMs)
                        }
                        "SET_AUDIO_FOCUS" -> {
                            val enabled = args.getBoolean("enabled", true)
                            setAudioFocusEnabled(enabled)
                        }
                    }
                } catch (_: Exception) {}
                return com.google.common.util.concurrent.Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
            }
        }
        
mediaSession = MediaSession.Builder(this, activePlayer)
            .setSessionActivity(sessionActivityPendingIntent)
            .setCallback(callback)
            .build()
    }
    
    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
        return mediaSession
    }
    
    private fun initializeEqualizer() {
android.util.Log.d("MusicService", "initializeEqualizer: audioSessionId=${'$'}{activePlayer.audioSessionId}")
        equalizerManager = EqualizerManager(this)
        // Initialize equalizer and reverb when player has a valid audio session
val sessionId = activePlayer.audioSessionId
        if (sessionId != C.AUDIO_SESSION_ID_UNSET) {
            if (sessionId != lastAudioSessionId) {
                lastAudioSessionId = sessionId
                equalizerManager.initialize(sessionId)
                configureReverbForSession(sessionId)
            }
        }
    }
    
    private fun setupPlayerListener() {
activePlayer.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                updateNotification()
                
                // Initialize equalizer when player is ready and has audio session
                if (playbackState == Player.STATE_READY) {
                    // Ensure current app volume is applied as soon as ready
                    try { activePlayer.volume = uiToAmp(appVolumeUi) } catch (_: Exception) {}
                    val sessionId = activePlayer.audioSessionId
                    if (sessionId != C.AUDIO_SESSION_ID_UNSET && sessionId != lastAudioSessionId) {
                        android.util.Log.d("MusicService", "STATE_READY: initializing EQ for sessionId=${'$'}sessionId")
                        lastAudioSessionId = sessionId
                        equalizerManager.initialize(sessionId)
                        configureReverbForSession(sessionId)
                    }
                }
            }
            
override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (isPlaying && crossfadeEnabled) startCrossfadePolling() else stopCrossfadePolling()
                // Ensure app volume is applied when playback starts
                if (isPlaying) { try { activePlayer.volume = uiToAmp(appVolumeUi) } catch (_: Exception) {} }
                if (isPlaying) {
                    startForeground(NOTIFICATION_ID, createNotification())
                } else {
                    // Keep notification visible while paused
                    @Suppress("DEPRECATION")
                    stopForeground(false)
                    notificationManager.notify(NOTIFICATION_ID, createNotification())
                    
                    // Check if app is in background and no active activities
                    checkAndStopServiceIfNeeded()
                }
            }
            
            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                updateNotification()
                // If not using polling or user disabled experimental true crossfade, we still do minimal fade-in
                val prefs = getSharedPreferences("settings", 0)
                val exp = prefs.getBoolean("experimental_true_crossfade", true)
                if (!exp && crossfadeEnabled && crossfadeDurationMs > 0L) {
                    startFadeIn(crossfadeDurationMs)
                }
                // Defensive: ensure effects are bound after item transitions as some devices
                // only expose a stable session once the new item is active
                val sessionId = activePlayer.audioSessionId
                // Re-apply volume on item transitions
                try { activePlayer.volume = uiToAmp(appVolumeUi) } catch (_: Exception) {}
                if (sessionId != C.AUDIO_SESSION_ID_UNSET && sessionId != lastAudioSessionId) {
                    android.util.Log.d("MusicService", "onMediaItemTransition: initializing EQ for sessionId=${'$'}sessionId")
                    lastAudioSessionId = sessionId
                    try { equalizerManager.initialize(sessionId) } catch (_: Exception) {}
                    try { configureReverbForSession(sessionId) } catch (_: Exception) {}
                }
            }
        })
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Music Playback",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Controls for music playback"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(): Notification {
val mediaMetadata = activePlayer.mediaMetadata
        val isPlaying = activePlayer.isPlaying
        
        val playPauseAction = if (isPlaying) {
            NotificationCompat.Action(
                R.drawable.ic_pause_24,
                "Pause",
                createMediaActionPendingIntent("PAUSE")
            )
        } else {
            NotificationCompat.Action(
                R.drawable.ic_play_arrow_24,
                "Play",
                createMediaActionPendingIntent("PLAY")
            )
        }
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(mediaMetadata.title ?: "Unknown Title")
            .setContentText(mediaMetadata.artist ?: "Unknown Artist")
            .setSubText(mediaMetadata.albumTitle ?: "Unknown Album")
            .setLargeIcon(getCurrentLargeIcon())
            .setSmallIcon(R.drawable.ic_music_note)
            .setContentIntent(createContentIntent())
            .setDeleteIntent(createMediaActionPendingIntent("STOP"))
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .addAction(
                R.drawable.ic_skip_previous_24,
                "Previous",
                createMediaActionPendingIntent("PREVIOUS")
            )
            .addAction(
                R.drawable.ic_replay_10_24,
                "Rewind",
                createMediaActionPendingIntent("REWIND")
            )
            .addAction(playPauseAction)
            .addAction(
                R.drawable.ic_forward_30_24,
                "Fast Forward",
                createMediaActionPendingIntent("FAST_FORWARD")
            )
            .addAction(
                R.drawable.ic_skip_next_24,
                "Next",
                createMediaActionPendingIntent("NEXT")
            )
            .setStyle(
                MediaNotificationCompat.MediaStyle()
                    .setShowActionsInCompactView(1, 2, 3)
                    .setMediaSession(mediaSession?.sessionCompatToken)
            )
            .build()
    }
    
    private fun createContentIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
    
    private fun createMediaActionPendingIntent(action: String): PendingIntent {
        val intent = Intent(this, MediaActionReceiver::class.java).apply {
            this.action = action
        }
        return PendingIntent.getBroadcast(
            this,
            action.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
    
private fun updateNotification() {
        if (activePlayer.playbackState != Player.STATE_IDLE) {
            notificationManager.notify(NOTIFICATION_ID, createNotification())
        }
    }
    
    private fun getCurrentLargeIcon(): android.graphics.Bitmap? {
        // Attempt to retrieve cached artwork for current media item using minimal overhead.
        // We derive a pseudo Song-like structure from MediaMetadata for cache key stability.
val title = activePlayer.mediaMetadata.title?.toString() ?: ""
        val artist = activePlayer.mediaMetadata.artist?.toString() ?: ""
        val album = activePlayer.mediaMetadata.albumTitle?.toString() ?: ""
        if (title.isBlank() && artist.isBlank() && album.isBlank()) return null
        return try {
            val fakeSong = com.stash.stashwave.data.Song(
                id = 0L,
                title = title,
                artist = artist,
                album = album,
                duration = 0L,
                path = ""
            )
            val cache = com.stash.stashwave.artwork.ArtworkCache(this)
            cache.loadBitmapIfPresent(fakeSong)
        } catch (_: Exception) {
            null
        }
    }
    
    fun getEqualizerManager(): EqualizerManager = equalizerManager
    
    private fun checkAndStopServiceIfNeeded() {
        // If app is not in foreground and music is paused, consider stopping service
        val activityManager = getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
        val appTasks = activityManager.getRunningTasks(1)
        
        val isAppInForeground = appTasks.isNotEmpty() && 
            appTasks[0].topActivity?.packageName == packageName
        
if (!isAppInForeground && !activePlayer.isPlaying) {
            // App is in background and music is not playing
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
if (!activePlayer.isPlaying) {
                    // Still not playing after delay, stop service
                    stopSelf()
                }
            }, 30000) // 30 second grace period
        }
    }
    
    fun setAppInForeground(inForeground: Boolean) {
        appInForeground = inForeground
    }

    // Live controls
fun setAppVolume(volume: Float) {
        appVolumeUi = volume.coerceIn(0f, 1f)
        val amp = uiToAmp(appVolumeUi)
        try { activePlayer.volume = amp } catch (_: Exception) {}
        try { sparePlayer?.volume = 0f } catch (_: Exception) {}
        try { getSharedPreferences("settings", 0).edit().putFloat("app_volume", appVolumeUi).apply() } catch (_: Exception) {}
    }

    fun setAudioFocusEnabled(enabled: Boolean) {
        audioFocusEnabled = enabled
        try { getSharedPreferences("settings", 0).edit().putBoolean("audio_focus_enabled", audioFocusEnabled).apply() } catch (_: Exception) {}
try { activePlayer.setAudioAttributes(audioAttributes, audioFocusEnabled) } catch (_: Exception) {}
        try { sparePlayer?.setAudioAttributes(audioAttributes, audioFocusEnabled) } catch (_: Exception) {}
    }

    fun setCrossfadeEnabled(enabled: Boolean) {
        crossfadeEnabled = enabled
        try { getSharedPreferences("settings", 0).edit().putBoolean("crossfade_enabled", crossfadeEnabled).apply() } catch (_: Exception) {}
    }

    fun setCrossfadeDuration(durationMs: Long) {
        crossfadeDurationMs = durationMs.coerceIn(0L, 5000L)
        try { getSharedPreferences("settings", 0).edit().putLong("crossfade_duration_ms", crossfadeDurationMs).apply() } catch (_: Exception) {}
    }

    private fun startFadeIn(durationMs: Long) {
        // Cancel any ongoing fade
        fadeRunnable?.let { mainHandler.removeCallbacks(it) }
        val startTime = System.currentTimeMillis()
        val startVol = 0f
        val endVol = uiToAmp(appVolumeUi)
        // Set initial
try { activePlayer.volume = startVol } catch (_: Exception) {}
        val runnable = object : Runnable {
            override fun run() {
                val elapsed = System.currentTimeMillis() - startTime
                val fraction = (elapsed.toFloat() / durationMs.toFloat()).coerceIn(0f, 1f)
                val vol = startVol + (endVol - startVol) * fraction
try { activePlayer.volume = vol } catch (_: Exception) {}
                if (fraction < 1f) {
                    mainHandler.postDelayed(this, 16L)
                }
            }
        }
        fadeRunnable = runnable
        mainHandler.post(runnable)
    }

    private fun startCrossfadePolling() {
        if (crossfadeCheckRunnable != null) return
        val prefs = getSharedPreferences("settings", 0)
        val exp = prefs.getBoolean("experimental_true_crossfade", true)
        if (!exp || !crossfadeEnabled || crossfadeDurationMs <= 0L) return
        crossfadeCheckRunnable = object : Runnable {
            override fun run() {
                try {
                    val dur = activePlayer.duration
                    val pos = activePlayer.currentPosition
                    if (dur > 0 && pos >= 0) {
                        val remaining = dur - pos
                        if (!isCrossfading && remaining in 1..(crossfadeDurationMs + 200)) {
                            startTrueCrossfade()
                        }
                    }
                } catch (_: Exception) {}
                mainHandler.postDelayed(this, 200L)
            }
        }
        mainHandler.post(crossfadeCheckRunnable!!)
    }

    private fun stopCrossfadePolling() {
        crossfadeCheckRunnable?.let { mainHandler.removeCallbacks(it) }
        crossfadeCheckRunnable = null
    }

    private fun startTrueCrossfade() {
        // Determine the actual next media item index respecting shuffle and repeat
        val nextIndex = try { activePlayer.nextMediaItemIndex } catch (_: Exception) { C.INDEX_UNSET }
        if (nextIndex == C.INDEX_UNSET || nextIndex >= activePlayer.mediaItemCount) return
        val nextItem = try { activePlayer.getMediaItemAt(nextIndex) } catch (_: Exception) { null } ?: return
        val spare = sparePlayer ?: return
        isCrossfading = true
        try {
            spare.stop()
            spare.clearMediaItems()
            spare.volume = 0f
            spare.setAudioAttributes(audioAttributes, audioFocusEnabled)
            spare.setHandleAudioBecomingNoisy(true)
            spare.setMediaItem(nextItem)
            spare.prepare()
            spare.play()
        } catch (_: Exception) {
            isCrossfading = false
            return
        }
        val startTime = System.currentTimeMillis()
        val baseAmp = uiToAmp(appVolumeUi)
        val fromVol = baseAmp
        val toVol = baseAmp
        fadeRunnable?.let { mainHandler.removeCallbacks(it) }
        val runnable = object : Runnable {
            override fun run() {
                val elapsed = System.currentTimeMillis() - startTime
                val fraction = (elapsed.toFloat() / crossfadeDurationMs.toFloat()).coerceIn(0f, 1f)
                val oldVol = fromVol * (1f - fraction)
                val newVol = toVol * (fraction)
                try { activePlayer.volume = oldVol } catch (_: Exception) {}
                try { spare.volume = newVol } catch (_: Exception) {}
                if (fraction < 1f) {
                    mainHandler.postDelayed(this, 16L)
                } else {
                    // Switch session to spare and swap references
                    try {
                        mediaSession?.setPlayer(spare)
                        try { equalizerManager.initialize(spare.audioSessionId) } catch (_: Exception) {}
                        try { configureReverbForSession(spare.audioSessionId) } catch (_: Exception) {}
                    } catch (_: Exception) {}
                    try { activePlayer.pause() } catch (_: Exception) {}
                    try { activePlayer.seekToDefaultPosition(nextIndex) } catch (_: Exception) {}
                    try { activePlayer.stop() } catch (_: Exception) {}
                    // Make the old player a new spare
                    val old = activePlayer
                    activePlayer = spare
                    sparePlayer = old
                    try { sparePlayer?.clearMediaItems() } catch (_: Exception) {}
                    try { sparePlayer?.volume = 0f } catch (_: Exception) {}
                    isCrossfading = false
                    updateNotification()
                }
            }
        }
        fadeRunnable = runnable
        mainHandler.post(runnable)
    }

    fun setPlaybackSpeed(speed: Float) {
        currentSpeed = speed
try { activePlayer.playbackParameters = PlaybackParameters(currentSpeed, currentPitch) } catch (_: Exception) {}
    }

    fun setPlaybackPitch(pitch: Float) {
        currentPitch = pitch
try { activePlayer.playbackParameters = PlaybackParameters(currentSpeed, currentPitch) } catch (_: Exception) {}
    }

    fun setReverbPreset(preset: Short) {
        currentReverb = preset
        try {
            if (presetReverb != null) {
                presetReverb?.preset = preset
                presetReverb?.enabled = (preset != 0.toShort())
            } else {
val sessionId = activePlayer.audioSessionId
                if (sessionId != C.AUDIO_SESSION_ID_UNSET) {
                    configureReverbForSession(sessionId)
                }
            }
        } catch (_: Exception) {}
        try { getSharedPreferences("settings", 0).edit().putInt("reverb_preset", preset.toInt()).apply() } catch (_: Exception) {}
    }
    
    private fun configureReverbForSession(sessionId: Int) {
        try {
            try { presetReverb?.release() } catch (_: Exception) {}
            presetReverb = PresetReverb(0, sessionId).apply {
                preset = currentReverb
                enabled = (currentReverb != 0.toShort())
            }
        } catch (_: Exception) {
            // Device may not support PresetReverb; ignore gracefully
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
try { activePlayer.pause() } catch (_: Exception) {}
        try {
            stopForeground(true)
            stopSelf()
        } catch (_: Exception) {}
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        // Unregister preference listeners
        try { unregisterPreferenceListeners() } catch (_: Exception) {}
        try { presetReverb?.release() } catch (_: Exception) {}
        equalizerManager.release()
        mediaSession?.run {
activePlayer.release()
            release()
            mediaSession = null
        }
        super.onDestroy()
    }

    // Preference listeners to apply audio settings immediately and persistently
    private var settingsPrefsListener: android.content.SharedPreferences.OnSharedPreferenceChangeListener? = null
    private var defaultPrefsListener: android.content.SharedPreferences.OnSharedPreferenceChangeListener? = null

    private fun registerPreferenceListeners() {
        val settingsPrefs = getSharedPreferences("settings", 0)
        val defaultPrefs = PreferenceManager.getDefaultSharedPreferences(this)

        settingsPrefsListener = android.content.SharedPreferences.OnSharedPreferenceChangeListener { prefs, key ->
            when (key) {
                "app_volume" -> {
                    val v = prefs.getFloat("app_volume", 1.0f).coerceIn(0f, 1f)
                    setAppVolume(v)
                }
                "audio_focus_enabled" -> setAudioFocusEnabled(prefs.getBoolean("audio_focus_enabled", true))
                "crossfade_enabled" -> setCrossfadeEnabled(prefs.getBoolean("crossfade_enabled", false))
                "crossfade_duration_ms" -> setCrossfadeDuration(prefs.getLong("crossfade_duration_ms", 1000L))
                "reverb_preset" -> setReverbPreset(prefs.getInt("reverb_preset", 0).toShort())
                "experimental_true_crossfade" -> {
                    val enabled = prefs.getBoolean("experimental_true_crossfade", true)
                    if (enabled && activePlayer.isPlaying && crossfadeEnabled) startCrossfadePolling() else stopCrossfadePolling()
                }
                "playback_speed" -> setPlaybackSpeed(prefs.getFloat("playback_speed", 1.0f).coerceIn(0.25f, 2.5f))
                "pitch_semitones" -> {
                    val semi = prefs.getInt("pitch_semitones", 0)
                    val pitch = Math.pow(2.0, semi / 12.0).toFloat()
                    setPlaybackPitch(pitch)
                }
            }
        }
        defaultPrefsListener = android.content.SharedPreferences.OnSharedPreferenceChangeListener { prefs, key ->
            when (key) {
                "equalizer_enabled" -> equalizerManager.setEnabled(prefs.getBoolean("equalizer_enabled", false))
                "equalizer_preset" -> {
                    val name = prefs.getString("equalizer_preset", com.stash.stashwave.audio.EqualizerPreset.NORMAL.name)
                    try { equalizerManager.setPreset(com.stash.stashwave.audio.EqualizerPreset.valueOf(name ?: "NORMAL")) } catch (_: Exception) {}
                }
                "bass_boost_strength" -> equalizerManager.setBassBoost(prefs.getInt("bass_boost_strength", 0))
                "virtualizer_strength" -> equalizerManager.setVirtualizer(prefs.getInt("virtualizer_strength", 0))
                "loudness_enhancer_gain" -> equalizerManager.setLoudnessGain(prefs.getInt("loudness_enhancer_gain", 0))
            }
        }
        settingsPrefs.registerOnSharedPreferenceChangeListener(settingsPrefsListener)
        defaultPrefs.registerOnSharedPreferenceChangeListener(defaultPrefsListener)
    }

    private fun unregisterPreferenceListeners() {
        try { getSharedPreferences("settings", 0).unregisterOnSharedPreferenceChangeListener(settingsPrefsListener) } catch (_: Exception) {}
        try { PreferenceManager.getDefaultSharedPreferences(this).unregisterOnSharedPreferenceChangeListener(defaultPrefsListener) } catch (_: Exception) {}
        settingsPrefsListener = null
        defaultPrefsListener = null
    }
}
