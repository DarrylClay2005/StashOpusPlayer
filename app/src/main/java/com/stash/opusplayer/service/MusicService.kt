package com.stash.opusplayer.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.ComponentName
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.common.PlaybackParameters
import androidx.media3.exoplayer.SeekParameters
import android.media.audiofx.PresetReverb
import android.media.audiofx.LoudnessEnhancer
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import androidx.media3.session.MediaSessionService
import androidx.media3.ui.PlayerNotificationManager
import androidx.media3.session.SessionCommands
import com.stash.opusplayer.R
import androidx.preference.PreferenceManager
import com.stash.opusplayer.audio.EqualizerManager
import com.stash.opusplayer.audio.EqualizerPreset
import com.stash.opusplayer.audio.EnhancedAudioManager
import com.stash.opusplayer.audio.ProfessionalAudioProcessor
import com.stash.opusplayer.audio.SpectrumAnalyzer
import com.stash.opusplayer.audio.True8DAudioProcessor
import com.stash.opusplayer.audio.settings.EnhancedAudioSettings
import com.stash.opusplayer.data.Song
import com.stash.opusplayer.ui.MainActivity
import kotlin.math.pow
import kotlin.math.log10
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class MusicService : MediaSessionService() {
    // Service-wide scope for background work
    private val serviceJob = SupervisorJob()
    private val serviceScope = CoroutineScope(serviceJob + Dispatchers.Main)
    
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
    private lateinit var enhancedAudioManager: EnhancedAudioManager
    private lateinit var professionalAudioProcessor: ProfessionalAudioProcessor
    private lateinit var spectrumAnalyzer: SpectrumAnalyzer
    private lateinit var true8DAudioProcessor: True8DAudioProcessor
    private lateinit var enhancedAudioSettings: EnhancedAudioSettings

    // Sleep timer state
    private var sleepTimerHandler: android.os.Handler? = null
    private var sleepTimerRunnable: Runnable? = null
    private var sleepTimerEndAtMs: Long = 0L
    private var presetReverb: PresetReverb? = null
    private var lastAudioSessionId: Int = C.AUDIO_SESSION_ID_UNSET
    private var currentSpeed: Float = 1.0f
    private var currentPitch: Float = 1.0f
    private var currentReverb: Short = 0
    private lateinit var notificationManager: NotificationManager
    private var appInForeground = true
    private var stopServiceWhenPaused = false

    // Media3 notification manager that binds actions directly to the MediaSession/Player
    private var playerNotificationManager: PlayerNotificationManager? = null

    // Phase 2: App volume and crossfade controls
    // Store UI-domain volume [0..1]; map to amplitude using a perceptual curve when applying to ExoPlayer
    private var appVolumeUi: Float = 1.0f
    private val volumeGamma: Float = 2.0f
    private fun uiToAmp(v: Float): Float = v.coerceIn(0f, 1f).pow(volumeGamma)
    private var crossfadeEnabled: Boolean = false
    private var crossfadeDurationMs: Long = 1000L
    private var audioFocusEnabled: Boolean = true
    private var crossfadePollingEnabled: Boolean = true

    // AB repeat
    private val abRepeatManager by lazy { ABRepeatManager(this) }
    private var abCheckRunnable: Runnable? = null
    private val abToleranceMs: Long = 250L

    // Playback enhancements
    private var skipSilenceEnabled: Boolean = false
    private var exactSeeks: Boolean = true

    // ReplayGain settings
    private var rgEnabled: Boolean = false
    private var rgMode: String = "track" // "track" or "album"
    private var rgPreampDb: Float = 0f
    private var rgFallbackDb: Float = 0f
    private var rgPreventClipping: Boolean = true
    private var rgAllowBoost: Boolean = false

    // ReplayGain LoudnessEnhancer (separate from EQ stack)
    private var rgLoudness: LoudnessEnhancer? = null
    private var lastRgSessionId: Int = C.AUDIO_SESSION_ID_UNSET

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
        
        // Initialize enhanced audio settings manager
        enhancedAudioSettings = EnhancedAudioSettings(this)
        
        // Register preference listeners so audio settings persist and apply instantly
        registerPreferenceListeners()
        
        initializePlayers()
        initializeEqualizer()
        initializeEnhancedAudio()
        initializeProfessionalAudioProcessor()
        initializeSpectrumAnalyzer()
        initialize8DAudioEngine()
        initializeMediaSession()
        setupPlayerListener()
        // Attempt to restore last session queue before showing notification
        restoreQueueStateIfAny()
        setupPlayerNotification()
    }
    
private fun initializePlayers() {
        // Initialize 8D audio processor first
        true8DAudioProcessor = True8DAudioProcessor(this)
        
        // Configure a custom HTTP data source with a modern mobile user-agent for broader CDN compatibility
        val httpFactory = androidx.media3.datasource.DefaultHttpDataSource.Factory()
            .setUserAgent("Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36 StashAudio/8.1.6")
            .setAllowCrossProtocolRedirects(true)
        // Wrap http factory with DefaultDataSource so local file/content URIs continue to work
        val defaultDsFactory = androidx.media3.datasource.DefaultDataSource.Factory(this, httpFactory)
        val mediaSourceFactory = androidx.media3.exoplayer.source.DefaultMediaSourceFactory(defaultDsFactory)

        // Create custom renderers factory with audio processor
        val renderersFactory = androidx.media3.exoplayer.DefaultRenderersFactory(this).apply {
            setEnableAudioTrackPlaybackParams(true)
            // Note: 8D audio processor will be integrated via effect system in future versions
        }

activePlayer = ExoPlayer.Builder(this)
            .setRenderersFactory(renderersFactory)
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
            skipSilenceEnabled = prefs.getBoolean("skip_silence_enabled", false)
            exactSeeks = prefs.getBoolean("exact_seeks", true)
            crossfadePollingEnabled = prefs.getBoolean("crossfade_polling_enabled", true)
            // ReplayGain
            rgEnabled = prefs.getBoolean("replaygain_enabled", false)
            rgMode = prefs.getString("replaygain_mode", "track") ?: "track"
            rgPreampDb = prefs.getFloat("replaygain_preamp_db", 0f)
            rgFallbackDb = prefs.getFloat("replaygain_fallback_db", 0f)
            rgPreventClipping = prefs.getBoolean("replaygain_prevent_clipping", true)
            rgAllowBoost = prefs.getBoolean("replaygain_allow_boost", false)
        } catch (_: Exception) {}

        // Apply audio attributes with focus handling preference
try { activePlayer.setAudioAttributes(audioAttributes, audioFocusEnabled) } catch (_: Exception) {}
        try { activePlayer.setHandleAudioBecomingNoisy(true) } catch (_: Exception) {}
        try { activePlayer.volume = uiToAmp(appVolumeUi) } catch (_: Exception) {}
        try { activePlayer.setSkipSilenceEnabled(skipSilenceEnabled) } catch (_: Exception) {}
        try { activePlayer.setPauseAtEndOfMediaItems(false) } catch (_: Exception) {}
        applySeekParameters()

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
    
    private fun applySeekParameters() {
        try {
            val params = if (exactSeeks) SeekParameters.EXACT else SeekParameters.CLOSEST_SYNC
            try { activePlayer.setSeekParameters(params) } catch (_: Exception) {}
            try { sparePlayer?.setSeekParameters(params) } catch (_: Exception) {}
        } catch (_: Exception) {}
    }
    
    private fun runAudioTestMaxVolume() {
        try {
            android.util.Log.w("MusicService", "AUDIO_TEST_MAX_VOLUME: disabling effects and maxing volume")
            val settings = getSharedPreferences("settings", 0)
            settings.edit()
                .putFloat("app_volume", 1.0f)
                .putBoolean("crossfade_enabled", false)
                .putLong("crossfade_duration_ms", 0L)
                .putBoolean("skip_silence_enabled", false)
                .putBoolean("replaygain_enabled", false)
                .putInt("reverb_preset", 0)
                .putBoolean("audio_focus_enabled", true)
                .apply()
            // Disable EQ in default prefs as well
            PreferenceManager.getDefaultSharedPreferences(this).edit()
                .putBoolean("equalizer_enabled", false)
                .apply()
            // Apply live
            setAppVolume(1.0f)
            setCrossfadeEnabled(false)
            setCrossfadeDuration(0L)
            skipSilenceEnabled = false
            try { activePlayer.setSkipSilenceEnabled(false) } catch (_: Exception) {}
            try { sparePlayer?.setSkipSilenceEnabled(false) } catch (_: Exception) {}
            try { equalizerManager.setEnabled(false) } catch (_: Exception) {}
            setReverbPreset(0)
            rgEnabled = false
            clearReplayGainBoost()
            setAudioFocusEnabled(true)
            try { activePlayer.volume = 1f } catch (_: Exception) {}
        } catch (_: Exception) {}
    }
    
    private fun replaceQueueAndPlay(args: android.os.Bundle) {
        try {
            val uris = args.getStringArrayList("uris") ?: arrayListOf()
            val titles = args.getStringArrayList("titles") ?: arrayListOf()
            val artists = args.getStringArrayList("artists") ?: arrayListOf()
            val albums = args.getStringArrayList("albums") ?: arrayListOf()
            val index = args.getInt("index", 0).coerceAtLeast(0)
            if (uris.isEmpty()) return
            android.util.Log.w("MusicService", "REPLACE_QUEUE_AND_PLAY: items=${uris.size} index=$index first=${uris.firstOrNull()}")
            cancelCrossfadeAndFocusActive()
            try { activePlayer.pause() } catch (_: Exception) {}
            try { activePlayer.stop() } catch (_: Exception) {}
            try { activePlayer.clearMediaItems() } catch (_: Exception) {}
            val items = mutableListOf<MediaItem>()
            for (i in uris.indices) {
                val md = MediaMetadata.Builder()
                    .setTitle(titles.getOrNull(i) ?: "")
                    .setArtist(artists.getOrNull(i) ?: "")
                    .setAlbumTitle(albums.getOrNull(i) ?: "")
                    .build()
                items.add(
                    MediaItem.Builder().setUri(android.net.Uri.parse(uris[i])).setMediaMetadata(md).build()
                )
            }
            if (index < items.size) {
                try {
                    activePlayer.setMediaItems(items, index, 0)
                } catch (e: Exception) {
                    android.util.Log.e("MusicService", "setMediaItems(index) failed", e)
                    activePlayer.setMediaItems(items)
                    activePlayer.seekToDefaultPosition(index)
                }
            } else {
                activePlayer.setMediaItems(items)
            }
            try {
                android.util.Log.d("MusicService", "prepare+play: count=${items.size} idx=$index")
                activePlayer.prepare()
                activePlayer.playWhenReady = true
                activePlayer.play()
            } catch (e: Exception) {
                android.util.Log.e("MusicService", "prepare/play failed", e)
            }
            // Persist
            try { saveQueueState() } catch (_: Exception) {}
            // Ensure polling according to current settings
            if (crossfadePollingEnabled && crossfadeEnabled && crossfadeDurationMs > 0L) startCrossfadePolling() else stopCrossfadePolling()
        } catch (e: Exception) {
            android.util.Log.e("MusicService", "REPLACE_QUEUE_AND_PLAY failed", e)
        }
    }
    
    private fun dumpPlaybackState() {
        try {
            val sb = StringBuilder()
            val p = activePlayer
            val idx = try { p.currentMediaItemIndex } catch (_: Exception) { -1 }
            val count = try { p.mediaItemCount } catch (_: Exception) { 0 }
            val isPlaying = try { p.isPlaying } catch (_: Exception) { false }
            val ps = try { p.playbackState } catch (_: Exception) { -1 }
            val shuffle = try { p.shuffleModeEnabled } catch (_: Exception) { false }
            val repeat = try { p.repeatMode } catch (_: Exception) { Player.REPEAT_MODE_OFF }
            val hasNext = try { p.hasNextMediaItem() } catch (_: Exception) { false }
            val pos = try { p.currentPosition } catch (_: Exception) { 0L }
            val dur = try { p.duration } catch (_: Exception) { 0L }
            val vol = try { p.volume } catch (_: Exception) { -1f }
            sb.appendLine("--- DUMP_PLAYBACK_STATE ---")
            sb.appendLine("playing=$isPlaying state=$ps idx=$idx/$count hasNext=$hasNext pos=$pos dur=$dur")
            sb.appendLine("shuffle=$shuffle repeat=$repeat exactSeeks=$exactSeeks seekParams=${try { p.seekParameters } catch (_: Exception) { null }}")
            sb.appendLine("appVolumeUi=$appVolumeUi activeVol=$vol skipSilence=$skipSilenceEnabled crossfadeEnabled=$crossfadeEnabled cfDur=$crossfadeDurationMs cfPolling=$crossfadePollingEnabled rgEnabled=$rgEnabled allowBoost=$rgAllowBoost")
            try {
                val titles = (0 until count).mapNotNull { i ->
                    try { p.getMediaItemAt(i).mediaMetadata.title?.toString() ?: "" } catch (_: Exception) { null }
                }
                sb.appendLine("queueTitles=${titles.joinToString(prefix="[", postfix="]")}")
            } catch (_: Exception) {}
            android.util.Log.w("MusicService", sb.toString())
        } catch (_: Exception) {}
    }
    
    private fun initializeMediaSession() {
        val sessionActivityPendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val callback = object : MediaSession.Callback {
            override fun onConnect(
                session: MediaSession,
                controller: MediaSession.ControllerInfo
            ): MediaSession.ConnectionResult {
                val sessionCommands = SessionCommands.Builder().apply {
                    listOf(
                        "CANCEL_CROSSFADE",
                        "SET_SLEEP_TIMER",
                        "CANCEL_SLEEP_TIMER",
                        "SET_EQ_ENABLED",
                        "SET_EQ_PRESET",
                        "SET_EQ_BAND",
                        "SET_BASS_BOOST",
                        "SET_VIRTUALIZER",
                        "SET_SPEED",
                        "SET_PITCH",
                        "SET_REVERB",
                        "SET_APP_VOLUME",
                        "SET_CROSSFADE_ENABLED",
                        "SET_CROSSFADE_DURATION",
                        "SET_AUDIO_FOCUS",
                        "AUDIO_TEST_MAX_VOLUME",
                        "REPLACE_QUEUE_AND_PLAY",
                        "SET_CROSSFADE_POLLING_ENABLED",
                        "SKIP_TO_NEXT",
                        "SKIP_TO_PREVIOUS",
                        "DUMP_PLAYBACK_STATE",
                        "SET_ENHANCED_AUDIO_ENABLED",
                        "SET_AUDIO_PROFILE",
                        "SET_AUTO_PROFILE_SWITCHING",
                        "SET_CROSS_SYSTEM_SYNC",
                        "TOGGLE_PROFESSIONAL_PROCESSOR",
                        "SET_COMPRESSION_ENABLED",
                        "SET_COMPRESSION_THRESHOLD",
                        "SET_COMPRESSION_RATIO",
                        "SET_COMPRESSION_ATTACK",
                        "SET_COMPRESSION_RELEASE",
                        "SET_STEREO_WIDTH",
                        "SET_AUTO_GAIN_ENABLED",
                        "SET_TARGET_LUFS",
                        "SET_CROSSFEED_ENABLED",
                        "SET_TUBE_WARMTH",
                        "LOAD_AUDIO_PROFILE",
                        "TOGGLE_SPECTRUM_ANALYZER",
                        "SET_8D_AUDIO_ENABLED",
                        "SET_8D_AUDIO_INTENSITY",
                        "SET_8D_ROTATION_SPEED"
                    ).forEach { add(SessionCommand(it, android.os.Bundle.EMPTY)) }
                    // AB repeat controls
                    add(SessionCommand("SET_AB_ENABLED", android.os.Bundle.EMPTY))
                    add(SessionCommand("SET_AB_A", android.os.Bundle.EMPTY))
                    add(SessionCommand("SET_AB_B", android.os.Bundle.EMPTY))
                    add(SessionCommand("CLEAR_AB", android.os.Bundle.EMPTY))
                }.build()
                val playerCommands = Player.Commands.Builder().addAllCommands().build()
                return MediaSession.ConnectionResult.accept(sessionCommands, playerCommands)
            }
            override fun onCustomCommand(
                session: MediaSession,
                controller: MediaSession.ControllerInfo,
                customCommand: SessionCommand,
                args: android.os.Bundle
            ): com.google.common.util.concurrent.ListenableFuture<SessionResult> {
                try {
                    when (customCommand.customAction) {
                        "CANCEL_CROSSFADE" -> {
                            cancelCrossfadeAndFocusActive()
                        }
                        "SET_SLEEP_TIMER" -> {
                            val dur = args.getLong("duration_ms", 0L)
                            setSleepTimer(dur)
                        }
                        "CANCEL_SLEEP_TIMER" -> cancelSleepTimer()
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
equalizerManager.setPreset(com.stash.opusplayer.audio.EqualizerPreset.valueOf(name))
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
                            // If user sets duration to 0, disable crossfade to avoid inconsistent state
                            if (durMs <= 0L) {
                                setCrossfadeEnabled(false)
                            }
                        }
                        "SET_AUDIO_FOCUS" -> {
                            val enabled = args.getBoolean("enabled", true)
                            setAudioFocusEnabled(enabled)
                        }
                        "AUDIO_TEST_MAX_VOLUME" -> {
                            runAudioTestMaxVolume()
                        }
                        "REPLACE_QUEUE_AND_PLAY" -> {
                            replaceQueueAndPlay(args)
                        }
                        "SET_CROSSFADE_POLLING_ENABLED" -> {
                            crossfadePollingEnabled = args.getBoolean("enabled", true)
                            getSharedPreferences("settings", 0).edit().putBoolean("crossfade_polling_enabled", crossfadePollingEnabled).apply()
                            if (crossfadePollingEnabled && activePlayer.isPlaying && crossfadeEnabled) startCrossfadePolling() else stopCrossfadePolling()
                        }
                        "SKIP_TO_NEXT" -> {
                            // Only continue playing if already playing, don't auto-start
                            val wasPlaying = try { activePlayer.isPlaying } catch (_: Exception) { false }
                            cancelCrossfadeAndFocusActive()
                            try { activePlayer.seekToNextMediaItem() } catch (_: Exception) {}
                            // Only set playWhenReady if music was already playing
                            if (wasPlaying) {
                                try { activePlayer.playWhenReady = true } catch (_: Exception) {}
                            }
                        }
                        "SKIP_TO_PREVIOUS" -> {
                            // Only continue playing if already playing, don't auto-start
                            val wasPlaying = try { activePlayer.isPlaying } catch (_: Exception) { false }
                            cancelCrossfadeAndFocusActive()
                            try { activePlayer.seekToPreviousMediaItem() } catch (_: Exception) {}
                            // Only set playWhenReady if music was already playing
                            if (wasPlaying) {
                                try { activePlayer.playWhenReady = true } catch (_: Exception) {}
                            }
                        }
                        "DUMP_PLAYBACK_STATE" -> {
                            dumpPlaybackState()
                        }
                        // AB repeat commands
                        "SET_AB_ENABLED" -> {
                            val enabled = args.getBoolean("enabled", false)
                            abRepeatManager.setEnabled(enabled)
                            if (enabled && activePlayer.isPlaying) startAbCheckLoop() else if (!enabled) stopAbCheckLoop()
                        }
                        "SET_AB_A" -> {
                            val pos = args.getLong("position_ms", try { activePlayer.currentPosition } catch (_: Exception) { 0L })
                            val key = currentTrackKey()
                            if (key != null) abRepeatManager.setPointA(key, pos)
                        }
                        "SET_AB_B" -> {
                            val pos = args.getLong("position_ms", try { activePlayer.currentPosition } catch (_: Exception) { 0L })
                            val key = currentTrackKey()
                            if (key != null) abRepeatManager.setPointB(key, pos)
                        }
                        "CLEAR_AB" -> {
                            val key = currentTrackKey()
                            if (key != null) abRepeatManager.clearAllForTrack(key)
                        }
                        // Enhanced Audio Commands
                        "SET_ENHANCED_AUDIO_ENABLED" -> {
                            val enabled = args.getBoolean("enabled", false)
                            if (::enhancedAudioManager.isInitialized) {
                                enhancedAudioManager.setEnhancedAudioEnabled(enabled)
                            }
                        }
                        "SET_AUDIO_PROFILE" -> {
                            val profileName = args.getString("profile") ?: "BALANCED"
                            if (::enhancedAudioManager.isInitialized) {
                                try {
                                    val audioProfile = com.stash.opusplayer.audio.AudioProfile.valueOf(profileName)
                                    enhancedAudioManager.setAudioProfile(audioProfile)
                                    android.util.Log.d("MusicService", "Set audio profile to: $profileName")
                                } catch (e: Exception) {
                                    android.util.Log.e("MusicService", "Failed to set audio profile: $profileName", e)
                                }
                            }
                        }
                        "SET_AUTO_PROFILE_SWITCHING" -> {
                            val enabled = args.getBoolean("enabled", false)
                            if (::enhancedAudioManager.isInitialized) {
                                enhancedAudioManager.setAutoProfileSwitching(enabled)
                            }
                        }
                        "SET_CROSS_SYSTEM_SYNC" -> {
                            val enabled = args.getBoolean("enabled", true)
                            if (::enhancedAudioManager.isInitialized) {
                                enhancedAudioManager.setCrossSystemSync(enabled)
                            }
                        }
                        // Professional Audio Processor Commands
                        "TOGGLE_PROFESSIONAL_PROCESSOR" -> {
                            val enabled = args.getBoolean("enabled", false)
                            if (::professionalAudioProcessor.isInitialized) {
                                professionalAudioProcessor.setEnabled(enabled)
                                enhancedAudioSettings.setProfessionalProcessorEnabled(enabled)
                            }
                        }
                        "SET_COMPRESSION_ENABLED" -> {
                            val enabled = args.getBoolean("enabled", false)
                            if (::professionalAudioProcessor.isInitialized) {
                                professionalAudioProcessor.setCompressorEnabled(enabled)
                                enhancedAudioSettings.setCompressionEnabled(enabled)
                            }
                        }
                        "SET_COMPRESSION_THRESHOLD" -> {
                            val threshold = args.getFloat("threshold", -12f)
                            if (::professionalAudioProcessor.isInitialized) {
                                professionalAudioProcessor.setCompressorThreshold(threshold)
                                enhancedAudioSettings.setCompressionThreshold(threshold)
                            }
                        }
                        "SET_COMPRESSION_RATIO" -> {
                            val ratio = args.getFloat("ratio", 4f)
                            if (::professionalAudioProcessor.isInitialized) {
                                professionalAudioProcessor.setCompressorRatio(ratio)
                                enhancedAudioSettings.setCompressionRatio(ratio)
                            }
                        }
                        "SET_COMPRESSION_ATTACK" -> {
                            val attack = args.getFloat("attack", 5f)
                            if (::professionalAudioProcessor.isInitialized) {
                                professionalAudioProcessor.setCompressorAttack(attack)
                                enhancedAudioSettings.setCompressionAttack(attack)
                            }
                        }
                        "SET_COMPRESSION_RELEASE" -> {
                            val release = args.getFloat("release", 50f)
                            if (::professionalAudioProcessor.isInitialized) {
                                professionalAudioProcessor.setCompressorRelease(release)
                                enhancedAudioSettings.setCompressionRelease(release)
                            }
                        }
                        "SET_STEREO_WIDTH" -> {
                            val width = args.getFloat("width", 1f)
                            if (::professionalAudioProcessor.isInitialized) {
                                professionalAudioProcessor.setStereoWidth(width)
                            }
                        }
                        "SET_AUTO_GAIN_ENABLED" -> {
                            val enabled = args.getBoolean("enabled", false)
                            if (::professionalAudioProcessor.isInitialized) {
                                professionalAudioProcessor.setAutoGainEnabled(enabled)
                            }
                        }
                        "SET_TARGET_LUFS" -> {
                            val lufs = args.getFloat("lufs", -16f)
                            if (::professionalAudioProcessor.isInitialized) {
                                professionalAudioProcessor.setTargetLufs(lufs)
                            }
                        }
                        "SET_CROSSFEED_ENABLED" -> {
                            val enabled = args.getBoolean("enabled", false)
                            if (::professionalAudioProcessor.isInitialized) {
                                professionalAudioProcessor.setCrossfeedEnabled(enabled)
                            }
                        }
                        "SET_TUBE_WARMTH" -> {
                            val warmth = args.getFloat("warmth", 0f)
                            if (::professionalAudioProcessor.isInitialized) {
                                professionalAudioProcessor.setTubeWarmth(warmth)
                            }
                        }
                        "LOAD_AUDIO_PROFILE" -> {
                            val profileName = args.getString("profile") ?: "BALANCED"
                            if (::professionalAudioProcessor.isInitialized) {
                                try {
                                    // Load profile settings via EnhancedAudioSettings
                                    enhancedAudioSettings.setCurrentAudioProfile(profileName)
                                    loadProfessionalAudioProcessorSettings()
                                    android.util.Log.d("MusicService", "Loaded audio profile: $profileName")
                                } catch (e: Exception) {
                                    android.util.Log.e("MusicService", "Failed to load audio profile: $profileName", e)
                                }
                            }
                        }
                        "TOGGLE_SPECTRUM_ANALYZER" -> {
                            val enabled = args.getBoolean("enabled", true)
                            if (::spectrumAnalyzer.isInitialized) {
                                spectrumAnalyzer.setEnabled(enabled)
                            }
                        }
                        // 8D Audio Commands
                        "SET_8D_AUDIO_ENABLED" -> {
                            val enabled = args.getBoolean("enabled", false)
                            set8DAudioEnabled(enabled)
                        }
                        "SET_8D_AUDIO_INTENSITY" -> {
                            val intensity = args.getFloat("intensity", 1.0f)
                            set8DAudioIntensity(intensity)
                        }
                        "SET_8D_ROTATION_SPEED" -> {
                            val speed = args.getFloat("speed", 1.0f)
                            set8DAudioRotationSpeed(speed)
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
    
    // Robust player state handlers
    private fun handlePlayerReady() {
        try {
            // Ensure current app volume is applied as soon as ready
            val base = uiToAmp(appVolumeUi)
            android.util.Log.d("MusicService", "STATE_READY: set base volume=${base}")
            activePlayer.volume = base
            
            // Initialize audio session and effects
            initializeAudioSessionEffects()
            
            // Apply ReplayGain for current item (async parse)
            if (rgEnabled) applyReplayGainForCurrent()
            
        } catch (e: Exception) {
            android.util.Log.e("MusicService", "Error in handlePlayerReady", e)
        }
    }
    
    private fun handlePlayerEnded() {
        try {
            // Defensive auto-advance if something prevented Exo from moving to next
            val mode = try { activePlayer.repeatMode } catch (_: Exception) { Player.REPEAT_MODE_OFF }
            val hasNext = try { activePlayer.hasNextMediaItem() } catch (_: Exception) { false }
            if (mode != Player.REPEAT_MODE_ONE && hasNext) {
                try { 
                    activePlayer.seekToNextMediaItem() 
                    // Ensure audio effects remain active during transition
                    maintainAudioEffectsAfterTransition()
                } catch (_: Exception) {}
            }
        } catch (e: Exception) {
            android.util.Log.e("MusicService", "Error in handlePlayerEnded", e)
        }
    }
    
    private fun handlePlayerIdle() {
        try {
            // Release temporary audio effects when idle to save resources
            android.util.Log.d("MusicService", "Player idle - conserving resources")
        } catch (e: Exception) {
            android.util.Log.e("MusicService", "Error in handlePlayerIdle", e)
        }
    }
    
    private fun maintainAudioEffectsDuringBuffering() {
        try {
            // Keep audio effects active and ready during buffering
            val sessionId = activePlayer.audioSessionId
            if (sessionId != C.AUDIO_SESSION_ID_UNSET && sessionId == lastAudioSessionId) {
                // Verify effects are still bound to session
                ensureAudioEffectsIntegrity(sessionId)
            }
        } catch (e: Exception) {
            android.util.Log.e("MusicService", "Error maintaining effects during buffering", e)
        }
    }
    
    private fun initializeAudioSessionEffects() {
        try {
            val sessionId = activePlayer.audioSessionId
            if (sessionId != C.AUDIO_SESSION_ID_UNSET && sessionId != lastAudioSessionId) {
                android.util.Log.d("MusicService", "STATE_READY: initializing effects for sessionId=${'$'}sessionId")
                lastAudioSessionId = sessionId
                
                // Initialize core effects with error handling
                try {
                    equalizerManager.initialize(sessionId)
                } catch (e: Exception) {
                    android.util.Log.e("MusicService", "Failed to initialize equalizer", e)
                }
                
                try {
                    configureReverbForSession(sessionId)
                } catch (e: Exception) {
                    android.util.Log.e("MusicService", "Failed to configure reverb", e)
                }
                
                try {
                    ensureReplayGainLoudness(sessionId)
                } catch (e: Exception) {
                    android.util.Log.e("MusicService", "Failed to setup ReplayGain loudness", e)
                }
                
                // Initialize enhanced audio systems with better error handling
                initializeEnhancedAudioSystems(sessionId)
            }
        } catch (e: Exception) {
            android.util.Log.e("MusicService", "Error initializing audio session effects", e)
        }
    }
    
    private fun initializeEnhancedAudioSystems(sessionId: Int) {
        // Initialize enhanced audio manager systems with robust error handling
        if (::enhancedAudioManager.isInitialized) {
            try {
                enhancedAudioManager.initialize(sessionId, equalizerManager)
            } catch (e: Exception) {
                android.util.Log.e("MusicService", "Failed to initialize enhanced audio manager", e)
                try {
                    // Fallback to individual system initialization
                    enhancedAudioManager.getAdvancedEffects().initialize(sessionId)
                } catch (e2: Exception) {
                    android.util.Log.e("MusicService", "Fallback advanced effects init failed", e2)
                }
            }
        }
        
        // Initialize professional audio processor with error recovery
        if (::professionalAudioProcessor.isInitialized) {
            try {
                professionalAudioProcessor.initialize(sessionId)
                loadProfessionalAudioProcessorSettings()
            } catch (e: Exception) {
                android.util.Log.e("MusicService", "Failed to initialize professional audio processor", e)
            }
        }
        
        // Initialize spectrum analyzer with error recovery
        if (::spectrumAnalyzer.isInitialized) {
            try {
                spectrumAnalyzer.initialize(sessionId)
                loadSpectrumAnalyzerSettings()
            } catch (e: Exception) {
                android.util.Log.e("MusicService", "Failed to initialize spectrum analyzer", e)
            }
        }
        
        // Initialize 8D Audio processor
        if (::true8DAudioProcessor.isInitialized) {
            try {
                true8DAudioProcessor.initialize(sessionId)
                // Load saved settings
                val prefs = getSharedPreferences("settings", 0)
                val enabled = prefs.getBoolean("audio_8d_enabled", false)
                val intensity = prefs.getFloat("audio_8d_intensity", 1.0f)
                val speed = prefs.getFloat("audio_8d_rotation_speed", 1.0f)
                
                true8DAudioProcessor.setIntensity(intensity)
                true8DAudioProcessor.setRotationSpeed(speed)
                if (enabled) {
                    true8DAudioProcessor.setEnabled(true)
                }
                android.util.Log.d("MusicService", "8D Audio processor initialized with session")
            } catch (e: Exception) {
                android.util.Log.e("MusicService", "Failed to initialize 8D Audio processor", e)
            }
        }
    }
    
    private fun maintainAudioEffectsAfterTransition() {
        try {
            // Ensure effects remain active after track transitions
            val sessionId = activePlayer.audioSessionId
            if (sessionId != C.AUDIO_SESSION_ID_UNSET) {
                ensureAudioEffectsIntegrity(sessionId)
            }
        } catch (e: Exception) {
            android.util.Log.e("MusicService", "Error maintaining effects after transition", e)
        }
    }
    
    private fun ensureAudioEffectsIntegrity(sessionId: Int) {
        try {
            // Verify and restore audio effects if needed
            if (!equalizerManager.isInitialized()) {
                equalizerManager.initialize(sessionId)
            }
            
            // Check enhanced audio systems
            if (::enhancedAudioManager.isInitialized) {
                // Re-initialize if needed
                try {
                    if (enhancedAudioManager.enhancedAudioEnabled.value) {
                        enhancedAudioManager.initialize(sessionId, equalizerManager)
                    }
                } catch (e: Exception) {
                    android.util.Log.w("MusicService", "Enhanced audio re-init failed, continuing", e)
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("MusicService", "Error ensuring audio effects integrity", e)
        }
    }
    
    private fun updateAudioSessionEffectsIfNeeded() {
        try {
            val currentSessionId = activePlayer.audioSessionId
            if (currentSessionId != C.AUDIO_SESSION_ID_UNSET && currentSessionId != lastAudioSessionId) {
                android.util.Log.d("MusicService", "Audio session ID changed, updating effects: $lastAudioSessionId -> $currentSessionId")
                handleAudioSessionChange(currentSessionId)
            }
        } catch (e: Exception) {
            android.util.Log.e("MusicService", "Error updating audio session effects", e)
        }
    }
    
    private fun handleAudioSessionChange(newSessionId: Int) {
        try {
            android.util.Log.d("MusicService", "Handling audio session change to $newSessionId")
            lastAudioSessionId = newSessionId
            
            // Re-initialize all audio effects with new session
            if (::equalizerManager.isInitialized) {
                equalizerManager.release()
                equalizerManager.initialize(newSessionId)
            }
            
            // Re-initialize enhanced audio manager
            if (::enhancedAudioManager.isInitialized) {
                enhancedAudioManager.release()
                enhancedAudioManager.initialize(newSessionId, equalizerManager)
            }
            
            // Re-initialize professional audio processor
            if (::professionalAudioProcessor.isInitialized) {
                professionalAudioProcessor.release()
                professionalAudioProcessor.initialize(newSessionId)
                loadProfessionalAudioProcessorSettings()
            }
            
            // Re-initialize spectrum analyzer
            if (::spectrumAnalyzer.isInitialized) {
                spectrumAnalyzer.release()
                spectrumAnalyzer.initialize(newSessionId)
                loadSpectrumAnalyzerSettings()
            }
            
            // Re-configure reverb
            configureReverbForSession(newSessionId)
            
            // Re-configure ReplayGain
            ensureReplayGainLoudness(newSessionId)
            
        } catch (e: Exception) {
            android.util.Log.e("MusicService", "Error handling audio session change", e)
        }
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
    
    private fun initializeEnhancedAudio() {
        android.util.Log.d("MusicService", "initializeEnhancedAudio: starting advanced audio systems")
        enhancedAudioManager = EnhancedAudioManager(this)
        val sessionId = activePlayer.audioSessionId
        if (sessionId != C.AUDIO_SESSION_ID_UNSET) {
            enhancedAudioManager.initialize(sessionId, equalizerManager)
        }
    }
    
    private fun initializeProfessionalAudioProcessor() {
        android.util.Log.d("MusicService", "initializeProfessionalAudioProcessor: starting professional DSP")
        professionalAudioProcessor = ProfessionalAudioProcessor(this)
        val sessionId = activePlayer.audioSessionId
        if (sessionId != C.AUDIO_SESSION_ID_UNSET) {
            professionalAudioProcessor.initialize(sessionId)
            loadProfessionalAudioProcessorSettings()
        }
    }
    
    private fun initializeSpectrumAnalyzer() {
        android.util.Log.d("MusicService", "initializeSpectrumAnalyzer: starting real-time audio analysis")
        spectrumAnalyzer = SpectrumAnalyzer(this)
        val sessionId = activePlayer.audioSessionId
        if (sessionId != C.AUDIO_SESSION_ID_UNSET) {
            spectrumAnalyzer.initialize(sessionId)
            // Disable by default to save CPU - only enable when visualizer is actually shown
            spectrumAnalyzer.setEnabled(false)
            loadSpectrumAnalyzerSettings()
        }
    }
    
    private fun setupPlayerListener() {
        activePlayer.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                try {
                    android.util.Log.d(
                        "MusicService",
                        "onPlaybackStateChanged state=$playbackState playWhenReady=${activePlayer.playWhenReady} isPlaying=${activePlayer.isPlaying} idx=${activePlayer.currentMediaItemIndex} count=${activePlayer.mediaItemCount} vol=${activePlayer.volume}"
                    )
                } catch (_: Exception) {}
                
                when (playbackState) {
                    Player.STATE_READY -> {
                        handlePlayerReady()
                        // Ensure audio effects are properly initialized when ready
                        ensureAudioEffectsIntegrity(activePlayer.audioSessionId)
                    }
                    Player.STATE_ENDED -> {
                        handlePlayerEnded()
                    }
                    Player.STATE_IDLE -> {
                        handlePlayerIdle()
                    }
                    Player.STATE_BUFFERING -> {
                        // Maintain audio effects during buffering
                        maintainAudioEffectsDuringBuffering()
                    }
                }
                
                // Update audio session effects on all state changes
                updateAudioSessionEffectsIfNeeded()
            }
            
            override fun onAudioSessionIdChanged(audioSessionId: Int) {
                super.onAudioSessionIdChanged(audioSessionId)
                android.util.Log.d("MusicService", "Audio session changed: $lastAudioSessionId -> $audioSessionId")
                if (audioSessionId != lastAudioSessionId) {
                    handleAudioSessionChange(audioSessionId)
                }
            }

            override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
                try {
                    val idx = try { activePlayer.currentMediaItemIndex } catch (_: Exception) { -1 }
                    val uri = try { activePlayer.currentMediaItem?.localConfiguration?.uri?.toString() } catch (_: Exception) { null }
                    val title = try { activePlayer.mediaMetadata.title?.toString() } catch (_: Exception) { null }
                    android.util.Log.e(
                        "MusicService",
                        "onPlayerError: code=${error.errorCode} msg=${error.message} idx=$idx uri=$uri title=$title",
                        error
                    )
                } catch (_: Exception) {}
            }
            
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (isPlaying && crossfadeEnabled) startCrossfadePolling() else stopCrossfadePolling()
                if (isPlaying) startAbCheckLoop() else stopAbCheckLoop()
                // Ensure app volume is applied when playback starts
                if (isPlaying) { try { activePlayer.volume = uiToAmp(appVolumeUi) } catch (_: Exception) {} }
                // Notify widget to update
                try {
                    sendBroadcast(Intent(com.stash.opusplayer.widgets.PlayerWidgetProvider.ACTION_UPDATE)
                        .setComponent(ComponentName(this@MusicService, com.stash.opusplayer.widgets.PlayerWidgetProvider::class.java)))
                } catch (_: Exception) {}
                // Notification foreground/updates are handled by PlayerNotificationManager
                // Check if app is in background and no active activities when paused
                if (!isPlaying) {
                    checkAndStopServiceIfNeeded()
                }
                // Persist queue periodically
                try { saveQueueState() } catch (_: Exception) {}
            }
            
            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                try { android.util.Log.d("MusicService", "onMediaItemTransition reason=$reason idx=${activePlayer.currentMediaItemIndex}") } catch (_: Exception) {}
                // Persist queue on track change
                try { saveQueueState() } catch (_: Exception) {}
                // Request widget refresh
                try {
                    sendBroadcast(Intent(com.stash.opusplayer.widgets.PlayerWidgetProvider.ACTION_UPDATE)
                        .setComponent(ComponentName(this@MusicService, com.stash.opusplayer.widgets.PlayerWidgetProvider::class.java)))
                } catch (_: Exception) {}
                // Prefetch neighbor artwork to reduce flashes
                try { prefetchNeighborArtwork() } catch (_: Exception) {}
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
                    try { ensureReplayGainLoudness(sessionId) } catch (_: Exception) {}
                    // Re-initialize enhanced audio processors
                    if (::professionalAudioProcessor.isInitialized) {
                        try { professionalAudioProcessor.initialize(sessionId) } catch (_: Exception) {}
                    }
                    if (::spectrumAnalyzer.isInitialized) {
                        try { spectrumAnalyzer.initialize(sessionId) } catch (_: Exception) {}
                    }
                }
                // Apply ReplayGain for new item
                if (rgEnabled) applyReplayGainForCurrent()
                // Notify AB manager of track change
                try { abRepeatManager.onTrackChanged(currentTrackKey() ?: "") } catch (_: Exception) {}
                
                // Analyze new track for enhanced audio processing
                // TODO: Implement TrackMetadata class if needed
                /* 
                if (::enhancedAudioManager.isInitialized) {
                    try {
                        val metadata = TrackMetadata(
                            genre = activePlayer.mediaMetadata.genre?.toString(),
                            artist = activePlayer.mediaMetadata.artist?.toString(),
                            tempo = null,
                            year = try {
                                activePlayer.mediaMetadata.releaseYear?.toInt()
                            } catch (_: Exception) { null }
                        )
                        // Start audio analysis in background
serviceScope.launch(Dispatchers.IO) {
                            // This would normally get actual audio samples from the player
                            // For now we'll use a placeholder to enable the system
                            val dummySamples = FloatArray(1024) { 0.0f }
                            enhancedAudioManager.analyzeCurrentTrack(dummySamples, metadata)
                        }
                    } catch (_: Exception) {}
                }
                */
            }
        })
    }

    // Cancel any in-flight crossfade and ensure MediaSession is bound to activePlayer
    private fun cancelCrossfadeAndFocusActive() {
        try {
            // Stop polling and fades
            stopCrossfadePolling()
            fadeRunnable?.let { mainHandler.removeCallbacks(it) }
            fadeRunnable = null
            
            // Stop and reset spare player with better error recovery
            try { 
                sparePlayer?.pause()
                sparePlayer?.stop()
                sparePlayer?.clearMediaItems()
                sparePlayer?.volume = 0f
            } catch (e: Exception) {
                android.util.Log.e("MusicService", "Error resetting spare player during crossfade cancel", e)
            }
            
            isCrossfading = false
            
            // Ensure session uses active player with error recovery
            try { 
                mediaSession?.setPlayer(activePlayer)
                activePlayer.volume = uiToAmp(appVolumeUi)
                // Re-initialize audio effects if session changed
                val currentSessionId = activePlayer.audioSessionId
                if (currentSessionId != C.AUDIO_SESSION_ID_UNSET && currentSessionId != lastAudioSessionId) {
                    initializeAudioSessionEffects()
                }
            } catch (e: Exception) {
                android.util.Log.e("MusicService", "Error restoring active player after crossfade cancel", e)
            }
        } catch (e: Exception) {
            android.util.Log.e("MusicService", "Error in cancelCrossfadeAndFocusActive", e)
        }
    }

    // Persist/restore queue state
    private fun saveQueueState() {
        val prefs = getSharedPreferences("queue_state", 0).edit()
        try {
            val count = activePlayer.mediaItemCount
            val list = mutableListOf<org.json.JSONObject>()
            for (i in 0 until count) {
                val mi = try { activePlayer.getMediaItemAt(i) } catch (_: Exception) { null } ?: continue
                val obj = org.json.JSONObject().apply {
                    put("uri", mi.localConfiguration?.uri?.toString() ?: "")
                    val md = mi.mediaMetadata
                    put("title", md.title ?: "")
                    put("artist", md.artist ?: "")
                    put("album", md.albumTitle ?: "")
                }
                list.add(obj)
            }
            val arr = org.json.JSONArray(list)
            prefs.putString("items", arr.toString())
            prefs.putInt("index", activePlayer.currentMediaItemIndex)
            prefs.putLong("position", try { activePlayer.currentPosition } catch (_: Exception) { 0L })
            prefs.putBoolean("shuffle", activePlayer.shuffleModeEnabled)
            prefs.putInt("repeat", activePlayer.repeatMode)
        } catch (_: Exception) {}
        prefs.apply()
    }

    private fun restoreQueueStateIfAny() {
        val prefs = getSharedPreferences("queue_state", 0)
        val json = prefs.getString("items", null) ?: return
        try {
            val arr = org.json.JSONArray(json)
            val items = mutableListOf<MediaItem>()
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                val uri = android.net.Uri.parse(obj.optString("uri", ""))
                val md = MediaMetadata.Builder()
                    .setTitle(obj.optString("title", ""))
                    .setArtist(obj.optString("artist", ""))
                    .setAlbumTitle(obj.optString("album", ""))
                    .build()
                val mi = MediaItem.Builder().setUri(uri).setMediaMetadata(md).build()
                items.add(mi)
            }
            if (items.isNotEmpty()) {
                val index = prefs.getInt("index", 0).coerceIn(0, items.lastIndex)
                val pos = prefs.getLong("position", 0L).coerceAtLeast(0L)
                try {
                    // CRITICAL: Set playWhenReady to false to prevent auto-start
                    android.util.Log.w("MusicService", "restoreQueueStateIfAny: Setting playWhenReady=false to prevent auto-start")
                    activePlayer.playWhenReady = false
                    activePlayer.setMediaItems(items, index, pos)
                    activePlayer.prepare()
                } catch (_: Exception) {
                    android.util.Log.w("MusicService", "restoreQueueStateIfAny: Setting playWhenReady=false (exception path)")
                    activePlayer.playWhenReady = false
                    activePlayer.setMediaItems(items)
                    activePlayer.seekTo(index, pos)
                }
                // Restore shuffle/repeat
                try { activePlayer.shuffleModeEnabled = prefs.getBoolean("shuffle", activePlayer.shuffleModeEnabled) } catch (_: Exception) {}
                try { activePlayer.repeatMode = prefs.getInt("repeat", activePlayer.repeatMode) } catch (_: Exception) {}
                
                // Explicitly ensure playback does NOT start automatically
                android.util.Log.w("MusicService", "restoreQueueStateIfAny: Final check - setting playWhenReady=false")
                activePlayer.playWhenReady = false
            }
        } catch (_: Exception) {}
    }

    private fun toggleFavoriteForCurrent() {
        try {
            val mm = activePlayer.mediaMetadata
            val title = mm.title?.toString() ?: return
            val artist = mm.artist?.toString() ?: ""
            val album = mm.albumTitle?.toString() ?: ""
            val fallback = com.stash.opusplayer.data.Song(
                id = 0L,
                title = title,
                artist = artist,
                album = album,
                duration = try { activePlayer.duration.takeIf { it > 0 } ?: 0L } catch (_: Exception) { 0L },
                path = ""
            )
            val repo = com.stash.opusplayer.data.MusicRepository(this)
            // Do DB work off the main thread
            kotlinx.coroutines.GlobalScope.launch(kotlinx.coroutines.Dispatchers.IO) {
                try {
                    val isFav = repo.isFavorite(fallback.id)
                    if (isFav) repo.removeFromFavorites(fallback.id) else repo.addToFavorites(fallback)
                } catch (_: Exception) {}
            }
        } catch (_: Exception) {}
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

    private fun setupPlayerNotification() {
        val descriptionAdapter = object : PlayerNotificationManager.MediaDescriptionAdapter {
            override fun getCurrentContentTitle(player: Player): CharSequence {
                return player.mediaMetadata.title ?: "Unknown Title"
            }

            override fun createCurrentContentIntent(player: Player): PendingIntent? {
                return createContentIntent()
            }

            override fun getCurrentContentText(player: Player): CharSequence? {
                return player.mediaMetadata.artist
            }

            override fun getCurrentSubText(player: Player): CharSequence? {
                return player.mediaMetadata.albumTitle
            }

            override fun getCurrentLargeIcon(
                player: Player,
                callback: PlayerNotificationManager.BitmapCallback
            ): android.graphics.Bitmap? {
                // Try synchronous cache hit; for cache miss we skip to avoid blocking
                return getCurrentLargeIcon()
            }
        }

        val customActionReceiver = object : PlayerNotificationManager.CustomActionReceiver {
            override fun createCustomActions(context: android.content.Context, instanceId: Int): MutableMap<String, NotificationCompat.Action> {
                val actions = mutableMapOf<String, NotificationCompat.Action>()
                actions["REWIND_10"] = NotificationCompat.Action(
                    R.drawable.ic_replay_10_24,
                    "-10s",
                    createContentIntent() // content intent is fine; action will be handled in onCustomAction
                )
                actions["FF_30"] = NotificationCompat.Action(
                    R.drawable.ic_forward_30_24,
                    "+30s",
                    createContentIntent()
                )
                actions["TOGGLE_FAVORITE"] = NotificationCompat.Action(
                    R.drawable.ic_favorite_border,
                    "Favorite",
                    createContentIntent()
                )
                return actions
            }
            override fun getCustomActions(player: Player): MutableList<String> {
                // Show seek +/- and favorite in the notification row
                return mutableListOf("REWIND_10", "TOGGLE_FAVORITE", "FF_30")
            }
            override fun onCustomAction(player: Player, action: String, intent: Intent) {
                when (action) {
                    "REWIND_10" -> {
                        try { player.seekTo((player.currentPosition - 10_000).coerceAtLeast(0)) } catch (_: Exception) {}
                    }
                    "FF_30" -> {
                        val dur = try { player.duration } catch (_: Exception) { 0L }
                        if (dur > 0) try { player.seekTo((player.currentPosition + 30_000).coerceAtMost(dur)) } catch (_: Exception) {}
                    }
                    "TOGGLE_FAVORITE" -> toggleFavoriteForCurrent()
                }
            }
        }

        val builder = PlayerNotificationManager.Builder(this, NOTIFICATION_ID, CHANNEL_ID)
            .setMediaDescriptionAdapter(descriptionAdapter)
            .setChannelImportance(NotificationManager.IMPORTANCE_LOW)
            .setSmallIconResourceId(R.drawable.ic_music_note)
            .setCustomActionReceiver(customActionReceiver)
            .setNotificationListener(object : PlayerNotificationManager.NotificationListener {
                override fun onNotificationPosted(notificationId: Int, notification: Notification, ongoing: Boolean) {
                    if (ongoing) {
                        startForeground(notificationId, notification)
                    } else {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            stopForeground(STOP_FOREGROUND_DETACH)
                        } else {
                            @Suppress("DEPRECATION")
                            stopForeground(false)
                        }
                        notificationManager.notify(notificationId, notification)
                        // If paused and app is backgrounded, consider stopping service later
                        checkAndStopServiceIfNeeded()
                    }
                }

                override fun onNotificationCancelled(notificationId: Int, dismissedByUser: Boolean) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        stopForeground(STOP_FOREGROUND_REMOVE)
                    } else {
                        @Suppress("DEPRECATION")
                        stopForeground(true)
                    }
                    stopSelf()
                }
            })

        playerNotificationManager = builder.build().apply {
            setUsePreviousAction(true)
            setUseRewindAction(true)
            setUsePlayPauseActions(true)
            setUseFastForwardAction(true)
            setUseNextAction(true)
            mediaSession?.sessionCompatToken?.let { setMediaSessionToken(it) }
            setPlayer(activePlayer)
        }
    }

    private fun setSleepTimer(durationMs: Long) {
        cancelSleepTimer()
        if (durationMs <= 0L) return
        sleepTimerHandler = android.os.Handler(android.os.Looper.getMainLooper())
        sleepTimerEndAtMs = System.currentTimeMillis() + durationMs
        val runnable = Runnable {
            startFadeOutAndPause(8000L)
        }
        sleepTimerRunnable = runnable
        sleepTimerHandler?.postDelayed(runnable, durationMs)
    }

    private fun cancelSleepTimer() {
        sleepTimerRunnable?.let { sleepTimerHandler?.removeCallbacks(it) }
        sleepTimerRunnable = null
        sleepTimerHandler = null
        sleepTimerEndAtMs = 0L
    }

    private fun startFadeOutAndPause(durationMs: Long) {
        val startTime = System.currentTimeMillis()
        val startVol = try { activePlayer.volume } catch (_: Exception) { 1f }
        val runnable = object : Runnable {
            override fun run() {
                val elapsed = System.currentTimeMillis() - startTime
                val fraction = (elapsed.toFloat() / durationMs.toFloat()).coerceIn(0f, 1f)
                val vol = startVol * (1f - fraction)
                try { activePlayer.volume = vol } catch (_: Exception) {}
                if (fraction < 1f) {
                    mainHandler.postDelayed(this, 16L)
                } else {
                    try { activePlayer.pause() } catch (_: Exception) {}
                }
            }
        }
        mainHandler.post(runnable)
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
    
    
    private fun getCurrentLargeIcon(): android.graphics.Bitmap? {
        // Attempt to retrieve cached artwork for current media item using MetadataStorageManager
        val title = activePlayer.mediaMetadata.title?.toString() ?: ""
        val artist = activePlayer.mediaMetadata.artist?.toString() ?: ""
        val album = activePlayer.mediaMetadata.albumTitle?.toString() ?: ""
        if (title.isBlank() && artist.isBlank() && album.isBlank()) return null
        return try {
            val identifier = title.ifBlank { "$artist-$album" }
            com.stash.opusplayer.utils.MetadataStorageManager.loadArtworkBitmap(this, identifier)
        } catch (_: Exception) {
            null
        }
    }
    
    fun getEqualizerManager(): EqualizerManager = equalizerManager
    
    fun getEnhancedAudioManager(): EnhancedAudioManager = enhancedAudioManager
    
    fun getProfessionalAudioProcessor(): ProfessionalAudioProcessor = professionalAudioProcessor
    
    fun getSpectrumAnalyzer(): SpectrumAnalyzer = spectrumAnalyzer
    
    fun getEnhancedAudioSettings(): EnhancedAudioSettings = enhancedAudioSettings
    
    /**
     * Load saved settings for professional audio processor
     */
    private fun loadProfessionalAudioProcessorSettings() {
        try {
            professionalAudioProcessor.setEnabled(enhancedAudioSettings.isProfessionalProcessorEnabled())
            professionalAudioProcessor.setCompressorEnabled(enhancedAudioSettings.isCompressionEnabled())
            professionalAudioProcessor.setCompressorThreshold(enhancedAudioSettings.getCompressionThreshold())
            professionalAudioProcessor.setCompressorRatio(enhancedAudioSettings.getCompressionRatio())
            professionalAudioProcessor.setCompressorAttack(enhancedAudioSettings.getCompressionAttack())
            professionalAudioProcessor.setCompressorRelease(enhancedAudioSettings.getCompressionRelease())
            professionalAudioProcessor.setStereoWidth(enhancedAudioSettings.getStereoWidth())
            professionalAudioProcessor.setAutoGainEnabled(enhancedAudioSettings.isAutoGainEnabled())
            professionalAudioProcessor.setTargetLufs(enhancedAudioSettings.getTargetLufs())
            professionalAudioProcessor.setCrossfeedEnabled(enhancedAudioSettings.isCrossfeedEnabled())
            professionalAudioProcessor.setTubeWarmth(enhancedAudioSettings.getTubeWarmth())
            
            // Load audio profile
            try {
                val profileName = enhancedAudioSettings.getCurrentAudioProfile()
                // Apply the saved audio profile through enhanced audio manager
                if (::enhancedAudioManager.isInitialized) {
                    val audioProfile = com.stash.opusplayer.audio.AudioProfile.valueOf(profileName)
                    enhancedAudioManager.setAudioProfile(audioProfile)
                }
            } catch (e: Exception) {
                // Default to balanced profile if invalid
                android.util.Log.w("MusicService", "Invalid audio profile, defaulting to BALANCED", e)
                if (::enhancedAudioManager.isInitialized) {
                    enhancedAudioManager.setAudioProfile(com.stash.opusplayer.audio.AudioProfile.BALANCED)
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("MusicService", "Error loading professional audio processor settings", e)
        }
    }
    
    /**
     * Load saved settings for spectrum analyzer
     */
    private fun loadSpectrumAnalyzerSettings() {
        try {
            spectrumAnalyzer.setEnabled(enhancedAudioSettings.isSpectrumAnalyzerEnabled())
        } catch (e: Exception) {
            android.util.Log.e("MusicService", "Error loading spectrum analyzer settings", e)
        }
    }
    
    private fun checkAndStopServiceIfNeeded() {
        try {
            // If app is not in foreground and music is paused, consider stopping service
            // Use a simpler approach since getRunningTasks is deprecated and restricted
            val isAppInForeground = appInForeground // Use the flag we maintain
            if (!isAppInForeground && !activePlayer.isPlaying) {
                // App is in background and music is not playing
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    try {
                        if (!activePlayer.isPlaying) stopSelf()
                    } catch (_: Exception) {}
                }, 30000) // 30 second grace period
            }
        } catch (_: Exception) {
            // Ignore environment restrictions
        }
    }
    
    fun setAppInForeground(inForeground: Boolean) {
        appInForeground = inForeground
    }

    // Live controls
    fun setAppVolume(volume: Float) {
        appVolumeUi = volume.coerceIn(0f, 1f)
        val amp = uiToAmp(appVolumeUi)
        try { android.util.Log.d("MusicService", "setAppVolume ui=${appVolumeUi} amp=${amp}") } catch (_: Exception) {}
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
        // Apply immediately if playback is active
        if (crossfadeEnabled && activePlayer.isPlaying) {
            startCrossfadePolling()
        } else {
            stopCrossfadePolling()
        }
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
        if (!crossfadePollingEnabled || !crossfadeEnabled || crossfadeDurationMs <= 0L) return
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

    // AB repeat loop maintenance (~200ms). Lightweight check to seek to A when reaching B.
    private fun startAbCheckLoop() {
        if (abCheckRunnable != null) return
        if (!abRepeatManager.isEnabled()) return
        abCheckRunnable = object : Runnable {
            override fun run() {
                try {
                    if (abRepeatManager.isEnabled()) {
                        val key = currentTrackKey()
                        if (key != null) {
                            val points = abRepeatManager.getPoints(key)
                            if (points != null) {
                                val (a, b) = points
                                val pos = try { activePlayer.currentPosition } catch (_: Exception) { 0L }
                                if (a >= 0 && b > a && pos >= (b - abToleranceMs)) {
                                    try { activePlayer.seekTo(a) } catch (_: Exception) {}
                                }
                            }
                        }
                    }
                } catch (_: Exception) { }
                mainHandler.postDelayed(this, 200L)
            }
        }
        mainHandler.post(abCheckRunnable!!)
    }

    private fun stopAbCheckLoop() {
        abCheckRunnable?.let { mainHandler.removeCallbacks(it) }
        abCheckRunnable = null
    }

    private fun currentTrackKey(): String? {
        return try {
            activePlayer.currentMediaItem?.localConfiguration?.uri?.toString()
                ?: activePlayer.mediaMetadata.title?.toString()
        } catch (_: Exception) { null }
    }

    private fun startTrueCrossfade() {
        // Determine the actual next media item index respecting shuffle and repeat
        try { android.util.Log.d("MusicService", "startTrueCrossfade: enabled=$crossfadeEnabled dur=${crossfadeDurationMs}ms") } catch (_: Exception) {}
        val nextIndex = try { activePlayer.nextMediaItemIndex } catch (_: Exception) { C.INDEX_UNSET }
        if (nextIndex == C.INDEX_UNSET || nextIndex >= activePlayer.mediaItemCount) return
        val nextItem = try { activePlayer.getMediaItemAt(nextIndex) } catch (_: Exception) { null } ?: return
        val spare = sparePlayer ?: return
        isCrossfading = true
        
        // Prepare spare player with proper async handling to prevent any freezing
        kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Default).launch {
            try {
                // All player operations on background thread
                kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Main) {
                    try {
                        spare.stop()
                        spare.clearMediaItems()
                    } catch (_: Exception) {}
                }
                
                // Brief delay to ensure cleanup completes
                kotlinx.coroutines.delay(50)
                
                kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Main) {
                    try {
                        spare.setAudioAttributes(audioAttributes, audioFocusEnabled)
                        spare.setHandleAudioBecomingNoisy(true)
                        spare.setMediaItem(nextItem)
                        
                        // Apply enhancement flags before prepare
                        try { spare.setSkipSilenceEnabled(skipSilenceEnabled) } catch (_: Exception) {}
                        try { spare.setPauseAtEndOfMediaItems(false) } catch (_: Exception) {}
                        
                        // Prepare asynchronously
                        spare.prepare()
                    } catch (_: Exception) {
                        isCrossfading = false
                        return@withContext
                    }
                }
                
                // Wait for player to be ready with timeout
                val readyTimeout = System.currentTimeMillis() + 2000L
                while (!spare.isCommandAvailable(androidx.media3.common.Player.COMMAND_PLAY_PAUSE) && 
                       System.currentTimeMillis() < readyTimeout) {
                    kotlinx.coroutines.delay(50)
                }
                
                // Start crossfade on main thread
                kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Main) {
                    try {
                        if (spare.isCommandAvailable(androidx.media3.common.Player.COMMAND_PLAY_PAUSE)) {
                            spare.volume = 0f
                            spare.play()
                            startCrossfadeFade(spare)
                        } else {
                            isCrossfading = false
                        }
                    } catch (_: Exception) {
                        isCrossfading = false
                    }
                }
            } catch (_: Exception) {
                kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Main) {
                    isCrossfading = false
                }
            }
        }
    }
    
    private fun startCrossfadeFade(spare: ExoPlayer) {
        val startTime = System.currentTimeMillis()
        val baseAmp = uiToAmp(appVolumeUi)
        val fromVol = baseAmp
        val toVol = baseAmp
        val savedNextIndex = try { activePlayer.nextMediaItemIndex } catch (_: Exception) { C.INDEX_UNSET }
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
                        val spareSession = try { spare.audioSessionId } catch (_: Exception) { C.AUDIO_SESSION_ID_UNSET }
                        val activeSession = try { activePlayer.audioSessionId } catch (_: Exception) { C.AUDIO_SESSION_ID_UNSET }
                        android.util.Log.d(
                            "MusicService",
                            "crossfade swap: fromSession=$activeSession toSession=$spareSession nextIdx=$savedNextIndex"
                        )
                        mediaSession?.setPlayer(spare)
                        try { equalizerManager.initialize(spare.audioSessionId) } catch (_: Exception) {}
                        try { configureReverbForSession(spare.audioSessionId) } catch (_: Exception) {}
                    } catch (e: Exception) {
                        android.util.Log.e("MusicService", "crossfade swap setPlayer failed", e)
                    }
                    try { activePlayer.pause() } catch (_: Exception) {}
                    try { activePlayer.seekToDefaultPosition(savedNextIndex) } catch (_: Exception) {}
                    try { activePlayer.stop() } catch (_: Exception) {}
                    // Make the old player a new spare
                    val old = activePlayer
                    activePlayer = spare
                    sparePlayer = old
                    try { sparePlayer?.clearMediaItems() } catch (_: Exception) {}
                    try { sparePlayer?.volume = 0f } catch (_: Exception) {}
                    isCrossfading = false
                    // Ensure notification manager targets the new active player
                    try { playerNotificationManager?.setPlayer(activePlayer) } catch (_: Exception) {}
                    try { saveQueueState() } catch (_: Exception) {}
                    try {
                        android.util.Log.d(
                            "MusicService",
                            "crossfade complete: activeIdx=${try { activePlayer.currentMediaItemIndex } catch (_: Exception) { -1 }}"
                        )
                    } catch (_: Exception) {}
                }
            }
        }
        fadeRunnable = runnable
        mainHandler.post(runnable)
    }

    fun setPlaybackSpeed(speed: Float) {
        currentSpeed = speed
try { activePlayer.playbackParameters = PlaybackParameters(currentSpeed, currentPitch) } catch (_: Exception) {}
        // ReplayGain unaffected by speed
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

    // ReplayGain support
    private fun ensureReplayGainLoudness(sessionId: Int) {
        if (!rgAllowBoost) return // We only need LE if positive boost is allowed
        try {
            if (lastRgSessionId == sessionId && rgLoudness != null) return
            lastRgSessionId = sessionId
            try { rgLoudness?.release() } catch (_: Exception) {}
            rgLoudness = LoudnessEnhancer(sessionId).apply {
                enabled = true
                setTargetGain(0)
            }
        } catch (_: Exception) {
            // Device may not support LoudnessEnhancer; ignore
            rgLoudness = null
        }
    }

    private fun clearReplayGainBoost() {
        try { rgLoudness?.setTargetGain(0) } catch (_: Exception) {}
        // Reset player volume to app volume only
        try { activePlayer.volume = uiToAmp(appVolumeUi) } catch (_: Exception) {}
    }

    private fun applyReplayGainForCurrent() {
        try {
            val uri = activePlayer.currentMediaItem?.localConfiguration?.uri ?: return
            // Compute asynchronously to avoid blocking the main thread
serviceScope.launch(Dispatchers.IO) {
                val info = com.stash.opusplayer.utils.ReplayGainUtil.parseWithCache(this@MusicService, uri.toString())
                val pair = computeReplayGainFor(info)
                val amp = pair.first
                val leMb = pair.second
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    val vol = (uiToAmp(appVolumeUi) * amp).coerceIn(0f, 1f)
                    try { android.util.Log.d("MusicService", "applyReplayGainForCurrent: ui=${appVolumeUi} rgAmp=${amp} -> vol=${vol} le=${leMb}mB") } catch (_: Exception) {}
                    try { activePlayer.volume = vol } catch (_: Exception) {}
                    if (rgAllowBoost && leMb != 0) {
                        try { ensureReplayGainLoudness(activePlayer.audioSessionId) } catch (_: Exception) {}
                        try { rgLoudness?.setTargetGain(leMb) } catch (_: Exception) {}
                    } else {
                        try { rgLoudness?.setTargetGain(0) } catch (_: Exception) {}
                    }
                }
            }
        } catch (_: Exception) {}
    }

    // Returns Pair(ampMultiplierForPlayerVolume, positiveBoostMillibelsForLoudnessEnhancer)
    private fun computeReplayGainFor(info: com.stash.opusplayer.utils.ReplayGainUtil.Info?): Pair<Float, Int> {
        if (!rgEnabled) return 1f to 0
        val gainDbFromTag = when (rgMode) {
            "album" -> info?.albumGainDb
            else -> info?.trackGainDb
        }
        val peak = when (rgMode) {
            "album" -> info?.albumPeak ?: info?.trackPeak
            else -> info?.trackPeak ?: info?.albumPeak
        } ?: 1f

        // Choose db to apply
        var targetDb = (gainDbFromTag ?: rgFallbackDb) + rgPreampDb

        // Prevent clipping if requested
        if (rgPreventClipping && peak > 0f) {
            // Ensure amp * peak <= 1 => 10^(db/20) <= 1/peak => db <= 20*log10(1/peak)
            val maxDb = 20f * (log10(1f / peak))
            if (targetDb > maxDb) targetDb = maxDb
        }

        // Split into player volume part (<= 0 dB) and optional positive boost via LE
        val ampDbForPlayer = if (rgAllowBoost) targetDb.coerceAtMost(0f) else targetDb.coerceAtMost(0f)
        val amp = dbToAmp(ampDbForPlayer)
        val remainingBoostDb = if (rgAllowBoost) (targetDb - ampDbForPlayer) else 0f
        val leMb = if (remainingBoostDb > 0.05f) (remainingBoostDb * 100f).toInt() else 0
        return amp to leMb
    }

    private fun dbToAmp(db: Float): Float = 10f.pow(db / 20f)

    override fun onTaskRemoved(rootIntent: Intent?) {
try { activePlayer.pause() } catch (_: Exception) {}
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf()
        } catch (_: Exception) {}
        super.onTaskRemoved(rootIntent)
    }

override fun onDestroy() {
        try { serviceJob.cancel() } catch (_: Exception) {}
        // Persist last-known queue state
        try { saveQueueState() } catch (_: Exception) {}
        // Unregister preference listeners
        try { unregisterPreferenceListeners() } catch (_: Exception) {}
        try { presetReverb?.release() } catch (_: Exception) {}
        equalizerManager.release()
        if (::enhancedAudioManager.isInitialized) {
            enhancedAudioManager.release()
        }
        if (::professionalAudioProcessor.isInitialized) {
            professionalAudioProcessor.release()
        }
        if (::spectrumAnalyzer.isInitialized) {
            spectrumAnalyzer.release()
        }
        if (::true8DAudioProcessor.isInitialized) {
            try { true8DAudioProcessor.shutdown() } catch (_: Exception) {}
        }
        mediaSession?.run {
            try { activePlayer.release() } catch (_: Exception) {}
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
                    if (rgEnabled) applyReplayGainForCurrent()
                }
                "audio_focus_enabled" -> setAudioFocusEnabled(prefs.getBoolean("audio_focus_enabled", true))
                "crossfade_enabled" -> setCrossfadeEnabled(prefs.getBoolean("crossfade_enabled", false))
                "crossfade_duration_ms" -> setCrossfadeDuration(prefs.getLong("crossfade_duration_ms", 1000L))
                "skip_silence_enabled" -> {
                    skipSilenceEnabled = prefs.getBoolean("skip_silence_enabled", false)
                    try { activePlayer.setSkipSilenceEnabled(skipSilenceEnabled) } catch (_: Exception) {}
                    try { sparePlayer?.setSkipSilenceEnabled(skipSilenceEnabled) } catch (_: Exception) {}
                }
                "exact_seeks" -> {
                    exactSeeks = prefs.getBoolean("exact_seeks", true)
                    applySeekParameters()
                }
                // ReplayGain
                "replaygain_enabled", "replaygain_mode", "replaygain_preamp_db", "replaygain_fallback_db",
                "replaygain_prevent_clipping", "replaygain_allow_boost" -> {
                    rgEnabled = prefs.getBoolean("replaygain_enabled", rgEnabled)
                    rgMode = prefs.getString("replaygain_mode", rgMode) ?: rgMode
                    rgPreampDb = prefs.getFloat("replaygain_preamp_db", rgPreampDb)
                    rgFallbackDb = prefs.getFloat("replaygain_fallback_db", rgFallbackDb)
                    rgPreventClipping = prefs.getBoolean("replaygain_prevent_clipping", rgPreventClipping)
                    rgAllowBoost = prefs.getBoolean("replaygain_allow_boost", rgAllowBoost)
                    if (rgEnabled) applyReplayGainForCurrent() else clearReplayGainBoost()
                }
                "reverb_preset" -> setReverbPreset(prefs.getInt("reverb_preset", 0).toShort())
                "experimental_true_crossfade" -> {
                    val enabled = prefs.getBoolean("experimental_true_crossfade", true)
                    if (enabled && activePlayer.isPlaying && crossfadeEnabled) startCrossfadePolling() else stopCrossfadePolling()
                }
                "crossfade_polling_enabled" -> {
                    crossfadePollingEnabled = prefs.getBoolean("crossfade_polling_enabled", true)
                    if (crossfadePollingEnabled && activePlayer.isPlaying && crossfadeEnabled) startCrossfadePolling() else stopCrossfadePolling()
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
                    val name = prefs.getString("equalizer_preset", com.stash.opusplayer.audio.EqualizerPreset.FLAT.name)
                    try { equalizerManager.setPreset(com.stash.opusplayer.audio.EqualizerPreset.valueOf(name ?: "FLAT")) } catch (_: Exception) {}
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

    private fun prefetchNeighborArtwork() {
        try {
            val idx = activePlayer.currentMediaItemIndex
            val count = activePlayer.mediaItemCount
            if (count <= 0) return
            val targets = listOf(idx - 1, idx + 1).filter { it in 0 until count }
            for (i in targets) {
                val mi = try { activePlayer.getMediaItemAt(i) } catch (_: Exception) { null } ?: continue
                val title = mi.mediaMetadata.title?.toString() ?: ""
                val artist = mi.mediaMetadata.artist?.toString() ?: ""
                val album = mi.mediaMetadata.albumTitle?.toString() ?: ""
                if (title.isBlank() && artist.isBlank() && album.isBlank()) continue
                try {
                    val identifier = title.ifBlank { "$artist-$album" }
                    val bmp = com.stash.opusplayer.utils.MetadataStorageManager.loadArtworkBitmap(this, identifier)
                    if (bmp == null) {
                        // Skip online fetching for neighbor prefetch - focus on local storage only
serviceScope.launch(Dispatchers.IO) {
                            try {
                                val fakeSong = com.stash.opusplayer.data.Song(0L, title, artist, album, 0L, "")
                                com.stash.opusplayer.artwork.OnlineArtworkFetcher(this@MusicService).getOrFetch(fakeSong)
                            } catch (_: Exception) {}
                        }
                    }
                } catch (_: Exception) {}
            }
        } catch (_: Exception) {}
    }
    
    // True 8D Audio Processor initialization
    private fun initialize8DAudioEngine() {
        try {
            // Already initialized in initializePlayers() with ExoPlayer integration
            // Load saved settings and apply
            val prefs = getSharedPreferences("settings", 0)
            val enabled = prefs.getBoolean("audio_8d_enabled", false)
            val intensity = prefs.getFloat("audio_8d_intensity", 1.0f)
            val speed = prefs.getFloat("audio_8d_rotation_speed", 1.0f)
            
            true8DAudioProcessor.setIntensity(intensity)
            true8DAudioProcessor.setRotationSpeed(speed)
            if (enabled) {
                true8DAudioProcessor.setEnabled(true)
            }
            
            android.util.Log.d("MusicService", "True 8D Audio Processor initialized with real stereo panning")
        } catch (e: Exception) {
            android.util.Log.e("MusicService", "Failed to initialize 8D Audio Processor", e)
        }
    }
    
    // 8D Audio control methods
    private fun set8DAudioEnabled(enabled: Boolean) {
        try {
            getSharedPreferences("settings", 0).edit()
                .putBoolean("audio_8d_enabled", enabled)
                .apply()
            
            true8DAudioProcessor.setEnabled(enabled)
            android.util.Log.d("MusicService", "True 8D Audio: ${if (enabled) "enabled" else "disabled"} (with real L/R panning)")
        } catch (e: Exception) {
            android.util.Log.e("MusicService", "Failed to set 8D Audio enabled state", e)
        }
    }
    
    private fun set8DAudioIntensity(intensity: Float) {
        try {
            getSharedPreferences("settings", 0).edit()
                .putFloat("audio_8d_intensity", intensity)
                .apply()
            
            true8DAudioProcessor.setIntensity(intensity)
            android.util.Log.d("MusicService", "True 8D Audio intensity set to: $intensity")
        } catch (e: Exception) {
            android.util.Log.e("MusicService", "Failed to set 8D Audio intensity", e)
        }
    }
    
    private fun set8DAudioRotationSpeed(speed: Float) {
        try {
            getSharedPreferences("settings", 0).edit()
                .putFloat("audio_8d_rotation_speed", speed)
                .apply()
            
            true8DAudioProcessor.setRotationSpeed(speed)
            android.util.Log.d("MusicService", "True 8D Audio rotation speed set to: $speed")
        } catch (e: Exception) {
            android.util.Log.e("MusicService", "Failed to set 8D Audio rotation speed", e)
        }
    }
}
