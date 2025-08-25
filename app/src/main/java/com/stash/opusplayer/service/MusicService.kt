package com.stash.opusplayer.service

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
import com.stash.opusplayer.R
import com.stash.opusplayer.audio.EqualizerManager
import com.stash.opusplayer.data.Song
import com.stash.opusplayer.ui.MainActivity

class MusicService : MediaSessionService() {
    
    companion object {
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "music_playback"
    }
    
    private var mediaSession: MediaSession? = null
    private lateinit var player: ExoPlayer
    private lateinit var equalizerManager: EqualizerManager
    private var presetReverb: PresetReverb? = null
    private var lastAudioSessionId: Int = C.AUDIO_SESSION_ID_UNSET
    private var currentSpeed: Float = 1.0f
    private var currentPitch: Float = 1.0f
    private var currentReverb: Short = 0
    private lateinit var notificationManager: NotificationManager
    
    override fun onCreate() {
        super.onCreate()
        
        notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        createNotificationChannel()
        
        initializePlayer()
        initializeEqualizer()
        initializeMediaSession()
        setupPlayerListener()
    }
    
    private fun initializePlayer() {
        player = ExoPlayer.Builder(this)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                    .setUsage(C.USAGE_MEDIA)
                    .build(),
                true
            )
            .setHandleAudioBecomingNoisy(true)
            .build()
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
                        }
                        "SET_EQ_PRESET" -> {
                            val name = args.getString("preset") ?: "NORMAL"
                            try {
                                equalizerManager.setPreset(com.stash.opusplayer.audio.EqualizerPreset.valueOf(name))
                            } catch (_: Exception) {}
                        }
                        "SET_EQ_BAND" -> {
                            val band = args.getInt("band", 0)
                            val level = args.getFloat("level", 0f)
                            equalizerManager.setBandLevel(band, level)
                        }
                        "SET_BASS_BOOST" -> {
                            val strength = args.getInt("strength", 0)
                            equalizerManager.setBassBoost(strength)
                        }
                        "SET_VIRTUALIZER" -> {
                            val strength = args.getInt("strength", 0)
                            equalizerManager.setVirtualizer(strength)
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
                    }
                } catch (_: Exception) {}
                return com.google.common.util.concurrent.Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
            }
        }
        
        mediaSession = MediaSession.Builder(this, player)
            .setSessionActivity(sessionActivityPendingIntent)
            .setCallback(callback)
            .build()
    }
    
    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
        return mediaSession
    }
    
    private fun initializeEqualizer() {
        equalizerManager = EqualizerManager(this)
        // Initialize equalizer with audio session ID when player is ready
        val sessionId = player.audioSessionId
        if (sessionId != C.AUDIO_SESSION_ID_UNSET) {
            if (sessionId != lastAudioSessionId) {
                lastAudioSessionId = sessionId
                equalizerManager.initialize(sessionId)
                try {
                    presetReverb?.release()
                } catch (_: Exception) {}
                try {
                    presetReverb = PresetReverb(0, sessionId).apply {
                        enabled = true
                        preset = currentReverb
                    }
                } catch (_: Exception) {}
            }
        }
    }
    
    private fun setupPlayerListener() {
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                updateNotification()
                
                // Initialize equalizer when player is ready and has audio session
                if (playbackState == Player.STATE_READY) {
                    val sessionId = player.audioSessionId
                    if (sessionId != C.AUDIO_SESSION_ID_UNSET && sessionId != lastAudioSessionId) {
                        lastAudioSessionId = sessionId
                        equalizerManager.initialize(sessionId)
                        try {
                            presetReverb?.release()
                        } catch (_: Exception) {}
                        try {
                            presetReverb = PresetReverb(0, sessionId).apply {
                                enabled = true
                                preset = currentReverb
                            }
                        } catch (_: Exception) {}
                    }
                }
            }
            
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                updateNotification()
                if (isPlaying) {
                    startForeground(NOTIFICATION_ID, createNotification())
                } else {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        stopForeground(android.app.Service.STOP_FOREGROUND_REMOVE)
                    } else {
                        @Suppress("DEPRECATION")
                        stopForeground(false)
                    }
                }
            }
            
            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                updateNotification()
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
        val mediaMetadata = player.mediaMetadata
        val isPlaying = player.isPlaying
        
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
            .addAction(playPauseAction)
            .addAction(
                R.drawable.ic_skip_next_24,
                "Next",
                createMediaActionPendingIntent("NEXT")
            )
            .setStyle(
                MediaNotificationCompat.MediaStyle()
                    .setShowActionsInCompactView(0, 1, 2)
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
        if (player.playbackState != Player.STATE_IDLE) {
            notificationManager.notify(NOTIFICATION_ID, createNotification())
        }
    }
    
    private fun getCurrentLargeIcon(): android.graphics.Bitmap? {
        // Attempt to retrieve cached artwork for current media item using minimal overhead.
        // We derive a pseudo Song-like structure from MediaMetadata for cache key stability.
        val title = player.mediaMetadata.title?.toString() ?: ""
        val artist = player.mediaMetadata.artist?.toString() ?: ""
        val album = player.mediaMetadata.albumTitle?.toString() ?: ""
        if (title.isBlank() && artist.isBlank() && album.isBlank()) return null
        return try {
            val fakeSong = com.stash.opusplayer.data.Song(
                id = 0L,
                title = title,
                artist = artist,
                album = album,
                duration = 0L,
                path = ""
            )
            val cache = com.stash.opusplayer.artwork.ArtworkCache(this)
            cache.loadBitmapIfPresent(fakeSong)
        } catch (_: Exception) {
            null
        }
    }
    
    fun getEqualizerManager(): EqualizerManager = equalizerManager

    // Live controls
    fun setPlaybackSpeed(speed: Float) {
        currentSpeed = speed
        try { player.playbackParameters = PlaybackParameters(currentSpeed, currentPitch) } catch (_: Exception) {}
    }

    fun setPlaybackPitch(pitch: Float) {
        currentPitch = pitch
        try { player.playbackParameters = PlaybackParameters(currentSpeed, currentPitch) } catch (_: Exception) {}
    }

    fun setReverbPreset(preset: Short) {
        currentReverb = preset
        try { presetReverb?.preset = preset } catch (_: Exception) {}
    }
    
    override fun onDestroy() {
        try { presetReverb?.release() } catch (_: Exception) {}
        equalizerManager.release()
        mediaSession?.run {
            player.release()
            release()
            mediaSession = null
        }
        super.onDestroy()
    }
}
