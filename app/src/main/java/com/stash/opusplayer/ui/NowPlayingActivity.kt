package com.stash.opusplayer.ui

import android.content.ComponentName
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.SeekBar
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.bumptech.glide.Glide
import com.google.common.util.concurrent.MoreExecutors
import com.stash.opusplayer.R
import com.stash.opusplayer.audio.EqualizerManager
import com.stash.opusplayer.data.Song
import com.stash.opusplayer.databinding.ActivityNowPlayingBinding
import com.stash.opusplayer.player.MusicPlayerManager
import com.stash.opusplayer.service.MusicService
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
        intent.getParcelableExtra<Song>("song")?.let { song ->
            currentSong = song
            displaySongInfo(song)
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
        
        // Load album artwork
        if (!song.albumArt.isNullOrEmpty()) {
            val bitmap = metadataExtractor.decodeAlbumArt(song.albumArt)
            if (bitmap != null) {
                Glide.with(this)
                    .load(bitmap)
                    .placeholder(R.drawable.ic_music_note)
                    .error(R.drawable.ic_music_note)
                    .centerCrop()
                    .into(binding.albumArtwork)
            } else {
                setDefaultArtwork()
            }
        } else {
            setDefaultArtwork()
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
    
    override fun onDestroy() {
        super.onDestroy()
        stopProgressUpdates()
        musicPlayerManager?.release()
        mediaController?.release()
    }
}
