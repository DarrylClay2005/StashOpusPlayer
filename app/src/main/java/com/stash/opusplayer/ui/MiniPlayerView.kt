package com.stash.opusplayer.ui

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.AttributeSet
import android.view.LayoutInflater
import android.widget.FrameLayout
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.lifecycleScope
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.bumptech.glide.Glide
import com.google.common.util.concurrent.MoreExecutors
import com.stash.opusplayer.R
import com.stash.opusplayer.data.Song
import com.stash.opusplayer.databinding.MiniPlayerBinding
import com.stash.opusplayer.player.MusicPlayerManager
import com.stash.opusplayer.service.MusicService
import com.stash.opusplayer.utils.MetadataExtractor
import kotlinx.coroutines.launch

class MiniPlayerView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : FrameLayout(context, attrs, defStyleAttr) {

    private val binding: MiniPlayerBinding
    private var mediaController: MediaController? = null
    private var musicPlayerManager: MusicPlayerManager? = null
    private val metadataExtractor = MetadataExtractor(context)
    
    private val progressHandler = Handler(Looper.getMainLooper())
    private var progressRunnable: Runnable? = null
    
    private var currentSong: Song? = null
    private var lifecycleOwner: LifecycleOwner? = null

    init {
        binding = MiniPlayerBinding.inflate(LayoutInflater.from(context), this, true)
        setupUI()
        visibility = GONE // Initially hidden
    }

    fun initialize(lifecycleOwner: LifecycleOwner, musicPlayerManager: MusicPlayerManager) {
        this.lifecycleOwner = lifecycleOwner
        this.musicPlayerManager = musicPlayerManager
        
        connectToMediaController()
        observePlayerState()
    }

    private fun setupUI() {
        // Click on mini player opens full screen player
        binding.root.setOnClickListener {
            currentSong?.let { song ->
                val intent = Intent(context, NowPlayingActivity::class.java).apply {
                    putExtra("song", song)
                }
                context.startActivity(intent)
            }
        }

        // Control button listeners
        binding.miniPlayPauseButton.setOnClickListener {
            mediaController?.let { controller ->
                if (controller.isPlaying) {
                    controller.pause()
                } else {
                    controller.play()
                }
            }
        }

        binding.miniPreviousButton.setOnClickListener {
            mediaController?.seekToPrevious()
        }

        binding.miniNextButton.setOnClickListener {
            mediaController?.seekToNext()
        }
    }

    private fun connectToMediaController() {
        val sessionToken = SessionToken(context, ComponentName(context, MusicService::class.java))
        val controllerFuture = MediaController.Builder(context, sessionToken).buildAsync()
        
        controllerFuture.addListener({
            try {
                mediaController = controllerFuture.get()
                setupMediaControllerListeners()
            } catch (e: Exception) {
                // Handle connection failure
            }
        }, MoreExecutors.directExecutor())
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
        })
    }

    private fun observePlayerState() {
        lifecycleOwner?.let { owner ->
            musicPlayerManager?.let { manager ->
                owner.lifecycleScope.launch {
                    manager.currentSong.collect { song ->
                        if (song != null) {
                            currentSong = song
                            displaySongInfo(song)
                            show()
                        } else {
                            hide()
                        }
                    }
                }

                owner.lifecycleScope.launch {
                    manager.isPlaying.collect { isPlaying ->
                        updatePlayPauseButton(isPlaying)
                        if (isPlaying) {
                            startProgressUpdates()
                        } else {
                            stopProgressUpdates()
                        }
                    }
                }
            }
        }
    }

    private fun displaySongInfo(song: Song) {
        binding.miniSongTitle.text = song.displayName
        binding.miniArtistName.text = song.artistName
        
        // Load album artwork (prefer cached, fallback to embedded/online)
        val cached = metadataExtractor.loadCachedArtwork(context, song)
        val embedded = metadataExtractor.decodeAlbumArt(song.albumArt)
        if (cached != null) {
            Glide.with(context)
                .load(cached)
                .centerCrop()
                .into(binding.miniAlbumArt)
        } else if (embedded != null) {
            Glide.with(context)
                .load(embedded)
                .placeholder(R.drawable.ic_music_note)
                .error(R.drawable.ic_music_note)
                .centerCrop()
                .into(binding.miniAlbumArt)
        } else {
            setDefaultArtwork()
        }
        // Try online in background if enabled
        val prefs = context.getSharedPreferences("settings", 0)
        val allowOnline = prefs.getBoolean("fetch_artwork_online", true)
        if (allowOnline) {
            lifecycleOwner?.lifecycleScope?.launch {
                val fetcher = com.stash.opusplayer.artwork.OnlineArtworkFetcher(context)
                val file = fetcher.getOrFetch(song)
                if (file != null && song == currentSong) {
                    Glide.with(context)
                        .load(file)
                        .placeholder(R.drawable.ic_music_note)
                        .error(R.drawable.ic_music_note)
                        .centerCrop()
                        .into(binding.miniAlbumArt)
                }
            }
        }
    }

    private fun setDefaultArtwork() {
        Glide.with(context)
            .load(R.drawable.ic_music_note)
            .into(binding.miniAlbumArt)
    }

    private fun updateMediaInfo() {
        mediaController?.let { controller ->
            val mediaMetadata = controller.mediaMetadata
            binding.miniSongTitle.text = mediaMetadata.title ?: "Unknown Title"
            binding.miniArtistName.text = mediaMetadata.artist ?: "Unknown Artist"
        }
    }

    private fun updatePlayPauseButton(isPlaying: Boolean) {
        if (isPlaying) {
            binding.miniPlayPauseButton.setImageResource(R.drawable.ic_pause_24)
        } else {
            binding.miniPlayPauseButton.setImageResource(R.drawable.ic_play_arrow_24)
        }
    }

    private fun startProgressUpdates() {
        stopProgressUpdates()
        progressRunnable = object : Runnable {
            override fun run() {
                mediaController?.let { controller ->
                    updateProgressBar(controller.currentPosition, controller.duration)
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

    private fun updateProgressBar(currentPosition: Long, duration: Long) {
        if (duration > 0) {
            val progress = ((currentPosition.toFloat() / duration.toFloat()) * 100).toInt()
            binding.miniProgressBar.progress = progress
        }
    }

    fun show() {
        if (visibility != VISIBLE) {
            visibility = VISIBLE
            // Optional: Add slide up animation
            animate()
                .translationY(0f)
                .setDuration(300)
                .start()
        }
    }

    fun hide() {
        if (visibility == VISIBLE) {
            // Optional: Add slide down animation
            animate()
                .translationY(height.toFloat())
                .setDuration(300)
                .withEndAction {
                    visibility = GONE
                }
                .start()
        }
    }

    fun release() {
        stopProgressUpdates()
        mediaController?.release()
    }
}
