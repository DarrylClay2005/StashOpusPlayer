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
import androidx.media3.session.MediaSession
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
        
        mediaSession = MediaSession.Builder(this, player)
            .setSessionActivity(sessionActivityPendingIntent)
            .build()
    }
    
    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
        return mediaSession
    }
    
    private fun initializeEqualizer() {
        equalizerManager = EqualizerManager(this)
        // Initialize equalizer with audio session ID when player is ready
        player.audioSessionId.let { sessionId ->
            if (sessionId != C.AUDIO_SESSION_ID_UNSET) {
                equalizerManager.initialize(sessionId)
            }
        }
    }
    
    private fun setupPlayerListener() {
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                updateNotification()
                
                // Initialize equalizer when player is ready and has audio session
                if (playbackState == Player.STATE_READY) {
                    player.audioSessionId.let { sessionId ->
                        if (sessionId != C.AUDIO_SESSION_ID_UNSET) {
                            equalizerManager.initialize(sessionId)
                        }
                    }
                }
            }
            
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                updateNotification()
                if (isPlaying) {
                    startForeground(NOTIFICATION_ID, createNotification())
                } else {
                    stopForeground(android.app.Service.STOP_FOREGROUND_DETACH)
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
            .setLargeIcon(null as android.graphics.Bitmap?) // TODO: Load album art
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
    
    fun getEqualizerManager(): EqualizerManager = equalizerManager
    
    override fun onDestroy() {
        equalizerManager.release()
        mediaSession?.run {
            player.release()
            release()
            mediaSession = null
        }
        super.onDestroy()
    }
}
