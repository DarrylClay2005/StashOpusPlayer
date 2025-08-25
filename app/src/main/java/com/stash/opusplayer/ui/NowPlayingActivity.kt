package com.stash.opusplayer.ui

import android.content.ComponentName
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.SeekBar
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.common.PlaybackParameters
import androidx.media3.session.SessionToken
import com.bumptech.glide.Glide
import com.google.common.util.concurrent.MoreExecutors
import com.stash.opusplayer.R
import com.stash.opusplayer.audio.EqualizerManager
import com.stash.opusplayer.data.Song
import com.stash.opusplayer.databinding.ActivityNowPlayingBinding
import com.stash.opusplayer.player.MusicPlayerManager
import com.stash.opusplayer.service.MusicService
import androidx.core.os.bundleOf
import com.stash.opusplayer.utils.MetadataExtractor
import kotlinx.coroutines.launch
import java.util.concurrent.TimeUnit

class NowPlayingActivity : AppCompatActivity() {
    
    private lateinit var binding: ActivityNowPlayingBinding
    private var mediaController: MediaController? = null
    private var musicPlayerManager: MusicPlayerManager? = null
    private lateinit var metadataExtractor: MetadataExtractor
    
    private val progressHandler = Handler(Looper.getMainLooper())
    private var progressRunnable: Runnable? = null
    
    private var currentSong: Song? = null
    private var isUserSeeking = false
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityNowPlayingBinding.inflate(layoutInflater)
        setContentView(binding.root)
        
        metadataExtractor = MetadataExtractor(this)
        
        setupUI()
        connectToMediaController()
        setupPlayerManager()
        
        // Get song from intent
        val song: Song? = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra("song", Song::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra<Song>("song")
        }
        song?.let {
            currentSong = it
            displaySongInfo(it)
        }
    }
    
    private fun setupUI() {
        // Back button
        binding.backButton.setOnClickListener {
            finish()
        }
        
        // Playback controls
        binding.playPauseButton.setOnClickListener {
            mediaController?.let { controller ->
                if (controller.isPlaying) {
                    controller.pause()
                } else {
                    controller.play()
                }
            }
        }
        
        binding.previousButton.setOnClickListener {
            mediaController?.seekToPrevious()
        }
        
        binding.nextButton.setOnClickListener {
            mediaController?.seekToNext()
        }
        
        binding.shuffleButton.setOnClickListener {
            mediaController?.let { controller ->
                controller.shuffleModeEnabled = !controller.shuffleModeEnabled
                updateShuffleButton(controller.shuffleModeEnabled)
            }
        }
        
        binding.repeatButton.setOnClickListener {
            mediaController?.let { controller ->
                val nextMode = when (controller.repeatMode) {
                    Player.REPEAT_MODE_OFF -> Player.REPEAT_MODE_ALL
                    Player.REPEAT_MODE_ALL -> Player.REPEAT_MODE_ONE
                    else -> Player.REPEAT_MODE_OFF
                }
                controller.repeatMode = nextMode
                updateRepeatButton(nextMode)
            }
        }
        
        // Seek bar
        binding.seekBar.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                if (fromUser) {
                    binding.currentTime.text = formatTime(progress.toLong())
                }
            }
            
            override fun onStartTrackingTouch(seekBar: SeekBar?) {
                isUserSeeking = true
            }
            
            override fun onStopTrackingTouch(seekBar: SeekBar?) {
                isUserSeeking = false
                mediaController?.seekTo(seekBar?.progress?.toLong() ?: 0L)
            }
        })
        
        // Favorite button
        binding.favoriteButton.setOnClickListener {
            // Toggle favorite status
            currentSong?.let { song ->
                val isFavorite = !song.isFavorite
                updateFavoriteButton(isFavorite)
                currentSong = song.copy(isFavorite = isFavorite)
            }
        }

        // Audio controls
        setupAudioControls()
    }

    private fun setupAudioControls() {
        // Speed: map 0..175 -> 0.25x..2.0x (value/100 + 0.25)
        binding.speedSeek.max = 175
        binding.speedSeek.progress = 75 // 1.00x initial
        binding.speedLabel.text = "1.00x"
        binding.speedSeek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                val speed = 0.25f + (progress.toFloat() / 100f)
                binding.speedLabel.text = String.format("%.2fx", speed)
                mediaController?.let { controller ->
                    val current = controller.playbackParameters
                    try {
                        controller.playbackParameters = PlaybackParameters(speed, current.pitch)
                    } catch (_: Exception) { /* ignore */ }
                    // Send to service to keep ExoPlayer parameters in sync
                    try {
                        controller.sendCustomCommand(
                            androidx.media3.session.SessionCommand("SET_SPEED", android.os.Bundle.EMPTY),
                            bundleOf("speed" to speed)
                        )
                    } catch (_: Exception) { /* ignore */ }
                }
            }
            override fun onStartTrackingTouch(seekBar: SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: SeekBar?) {}
        })

        // Pitch semitones: -12..+12 -> pitch factor 2^(st/12)
        binding.pitchSeek.max = 24
        binding.pitchSeek.progress = 12 // 0 semitones
        binding.pitchLabel.text = "0 st"
        binding.pitchSeek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                val semitones = progress - 12
                binding.pitchLabel.text = "$semitones st"
                val pitch = Math.pow(2.0, semitones / 12.0).toFloat()
                mediaController?.let { controller ->
                    val current = controller.playbackParameters
                    try {
                        controller.playbackParameters = PlaybackParameters(current.speed, pitch)
                    } catch (_: Exception) { /* ignore */ }
                    try {
                        controller.sendCustomCommand(
                            androidx.media3.session.SessionCommand("SET_PITCH", android.os.Bundle.EMPTY),
                            bundleOf("pitch" to pitch)
                        )
                    } catch (_: Exception) { /* ignore */ }
                }
            }
            override fun onStartTrackingTouch(seekBar: SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: SeekBar?) {}
        })

        // Reverb 0..1000 mapped to Preset (0..6 typical). We'll approximate presets by buckets.
        binding.reverbSeek.max = 1000
        binding.reverbSeek.progress = 0
        binding.reverbLabel.text = "Reverb 0%"
        binding.reverbSeek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                binding.reverbLabel.text = "Reverb ${progress / 10}%"
                val preset: Short = when {
                    progress < 50 -> 0 // none
                    progress < 200 -> 1
                    progress < 400 -> 2
                    progress < 600 -> 3
                    progress < 800 -> 4
                    progress < 950 -> 5
                    else -> 6
                }.toShort()
mediaController?.sendCustomCommand(
                    androidx.media3.session.SessionCommand("SET_REVERB", android.os.Bundle.EMPTY),
                    bundleOf("preset" to preset.toInt())
                )
            }
            override fun onStartTrackingTouch(seekBar: SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: SeekBar?) {}
        })
    }
    
    private fun connectToMediaController() {
        val sessionToken = SessionToken(this, ComponentName(this, MusicService::class.java))
        val controllerFuture = MediaController.Builder(this, sessionToken).buildAsync()
        
        controllerFuture.addListener({
            mediaController = controllerFuture.get()
            setupMediaControllerListeners()
            updateUIFromController()
        }, MoreExecutors.directExecutor())
    }
    
    private fun setupPlayerManager() {
        musicPlayerManager = MusicPlayerManager(this).apply {
            initialize()
        }
        
        // Observe player state changes
        lifecycleScope.launch {
            musicPlayerManager?.currentSong?.collect { song ->
                song?.let {
                    currentSong = it
                    displaySongInfo(it)
                }
            }
        }
        
        lifecycleScope.launch {
            musicPlayerManager?.isPlaying?.collect { isPlaying ->
                updatePlayPauseButton(isPlaying)
                if (isPlaying) {
                    startProgressUpdates()
                } else {
                    stopProgressUpdates()
                }
            }
        }
    }
    
    private fun setupMediaControllerListeners() {
        mediaController?.addListener(object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                updatePlayPauseButton(isPlaying)
                if (isPlaying) {
                    startProgressUpdates()
                } else {
                    stopProgressUpdates()
                }
            }
            
            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                updateMediaInfo()
            }
            
            override fun onShuffleModeEnabledChanged(shuffleModeEnabled: Boolean) {
                updateShuffleButton(shuffleModeEnabled)
            }
            
            override fun onRepeatModeChanged(repeatMode: Int) {
                updateRepeatButton(repeatMode)
            }
        })
    }
    
    private fun displaySongInfo(song: Song) {
        binding.songTitle.text = song.displayName
        binding.artistName.text = song.artistName
        binding.albumName.text = song.albumName
        
        // Load album artwork (prefer cached for speed; fallback to embedded/online)
        val cached = metadataExtractor.loadCachedArtwork(this, song)
        val embedded = metadataExtractor.decodeAlbumArt(song.albumArt)
        if (cached != null) {
            Glide.with(this)
                .load(cached)
                .centerCrop()
                .into(binding.albumArtwork)
            // Set blurred backdrop
            try {
                Glide.with(this)
                    .load(cached)
                    .apply(com.bumptech.glide.request.RequestOptions.bitmapTransform(jp.wasabeef.glide.transformations.BlurTransformation(25, 3)))
                    .into(binding.backdropImage)
            } catch (_: Exception) {}
        } else if (embedded != null) {
            Glide.with(this)
                .load(embedded)
                .placeholder(R.drawable.ic_music_note)
                .error(R.drawable.ic_music_note)
                .centerCrop()
                .into(binding.albumArtwork)
            // Set blurred backdrop
            try {
                Glide.with(this)
                    .load(embedded)
                    .apply(com.bumptech.glide.request.RequestOptions.bitmapTransform(jp.wasabeef.glide.transformations.BlurTransformation(25, 3)))
                    .into(binding.backdropImage)
            } catch (_: Exception) {}
        } else {
            setDefaultArtwork()
        }
        
        // Then try online in background if enabled to improve when missing
        val prefs = getSharedPreferences("settings", 0)
        val allowOnline = prefs.getBoolean("fetch_artwork_online", true)
        if (allowOnline) {
            lifecycleScope.launch {
                val fetcher = com.stash.opusplayer.artwork.OnlineArtworkFetcher(this@NowPlayingActivity)
                val file = fetcher.getOrFetch(song)
                if (file != null && song == currentSong) {
                    Glide.with(this@NowPlayingActivity)
                        .load(file)
                        .placeholder(R.drawable.ic_music_note)
                        .error(R.drawable.ic_music_note)
                        .centerCrop()
                        .into(binding.albumArtwork)
                    try {
                        Glide.with(this@NowPlayingActivity)
                            .load(file)
                            .apply(com.bumptech.glide.request.RequestOptions.bitmapTransform(jp.wasabeef.glide.transformations.BlurTransformation(25, 3)))
                            .into(binding.backdropImage)
                    } catch (_: Exception) {}
                }
            }
        }
        
        updateFavoriteButton(song.isFavorite)
    }
    
    private fun setDefaultArtwork() {
        Glide.with(this)
            .load(R.drawable.ic_music_note)
            .into(binding.albumArtwork)
    }
    
    private fun updateUIFromController() {
        mediaController?.let { controller ->
            updatePlayPauseButton(controller.isPlaying)
            updateShuffleButton(controller.shuffleModeEnabled)
            updateRepeatButton(controller.repeatMode)
            updateSeekBar(controller.currentPosition, controller.duration)
            
            if (controller.isPlaying) {
                startProgressUpdates()
            }
        }
    }
    
    private fun updateMediaInfo() {
        mediaController?.let { controller ->
            val mediaMetadata = controller.mediaMetadata
            binding.songTitle.text = mediaMetadata.title ?: "Unknown Title"
            binding.artistName.text = mediaMetadata.artist ?: "Unknown Artist"
            binding.albumName.text = mediaMetadata.albumTitle ?: "Unknown Album"
        }
    }
    
    private fun updatePlayPauseButton(isPlaying: Boolean) {
        if (isPlaying) {
            binding.playPauseButton.setImageResource(R.drawable.ic_pause_24)
        } else {
            binding.playPauseButton.setImageResource(R.drawable.ic_play_arrow_24)
        }
    }
    
    private fun updateShuffleButton(enabled: Boolean) {
        binding.shuffleButton.alpha = if (enabled) 1.0f else 0.5f
    }
    
    private fun updateRepeatButton(repeatMode: Int) {
        when (repeatMode) {
            Player.REPEAT_MODE_OFF -> {
                binding.repeatButton.setImageResource(R.drawable.ic_repeat)
                binding.repeatButton.alpha = 0.5f
            }
            Player.REPEAT_MODE_ALL -> {
                binding.repeatButton.setImageResource(R.drawable.ic_repeat)
                binding.repeatButton.alpha = 1.0f
            }
            Player.REPEAT_MODE_ONE -> {
                binding.repeatButton.setImageResource(R.drawable.ic_repeat_one)
                binding.repeatButton.alpha = 1.0f
            }
        }
    }
    
    private fun updateFavoriteButton(isFavorite: Boolean) {
        if (isFavorite) {
            binding.favoriteButton.setImageResource(R.drawable.ic_favorite)
            binding.favoriteButton.alpha = 1.0f
        } else {
            binding.favoriteButton.setImageResource(R.drawable.ic_favorite_border)
            binding.favoriteButton.alpha = 0.7f
        }
    }
    
    private fun startProgressUpdates() {
        stopProgressUpdates()
        progressRunnable = object : Runnable {
            override fun run() {
                if (!isUserSeeking) {
                    mediaController?.let { controller ->
                        updateSeekBar(controller.currentPosition, controller.duration)
                    }
                }
                progressHandler.postDelayed(this, 1000)
            }
        }
        progressRunnable?.let { progressHandler.post(it) }
    }
    
    private fun stopProgressUpdates() {
        progressRunnable?.let { progressHandler.removeCallbacks(it) }
        progressRunnable = null
    }
    
    private fun updateSeekBar(currentPosition: Long, duration: Long) {
        if (duration > 0) {
            binding.seekBar.max = duration.toInt()
            binding.seekBar.progress = currentPosition.toInt()
            binding.currentTime.text = formatTime(currentPosition)
            binding.totalTime.text = formatTime(duration)
        }
    }
    
    private fun formatTime(milliseconds: Long): String {
        val minutes = TimeUnit.MILLISECONDS.toMinutes(milliseconds)
        val seconds = TimeUnit.MILLISECONDS.toSeconds(milliseconds) - 
                      TimeUnit.MINUTES.toSeconds(minutes)
        return String.format("%d:%02d", minutes, seconds)
    }
    
    override fun onStop() {
        super.onStop()
        stopProgressUpdates()
    }

    override fun onStart() {
        super.onStart()
        mediaController?.let { if (it.isPlaying) startProgressUpdates() }
    }

    override fun onDestroy() {
        super.onDestroy()
        stopProgressUpdates()
        musicPlayerManager?.release()
        mediaController?.release()
    }
}
