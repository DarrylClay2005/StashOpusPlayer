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
import com.stash.opusplayer.ui.appearance.AppearancePreferences
import android.animation.ObjectAnimator
import android.view.animation.LinearInterpolator
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
    private var spinningAnimator: ObjectAnimator? = null

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
            val intent = Intent(context, NowPlayingActivity::class.java).apply {
                currentSong?.let { putExtra("song", it) }
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            try {
                context.startActivity(intent)
            } catch (_: Exception) {
                // best-effort fallback without extras
                try { context.startActivity(Intent(context, NowPlayingActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } catch (_: Exception) {}
            }
        }

        // Control button listeners with improved responsiveness and visual feedback
        binding.miniPlayPauseButton.setOnClickListener { view ->
            // Add visual feedback
            view.animate().scaleX(0.9f).scaleY(0.9f).setDuration(100)
                .withEndAction {
                    view.animate().scaleX(1.0f).scaleY(1.0f).setDuration(100).start()
                }.start()
            
            // Immediate action with fallback
            try {
                mediaController?.let { controller ->
                    if (controller.isPlaying) {
                        controller.pause()
                    } else {
                        controller.play()
                    }
                } ?: run {
                    // Fallback to player manager if controller not ready
                    musicPlayerManager?.let { manager ->
                        if (manager.isPlaying.value) {
                            manager.pause()
                        } else {
                            manager.play()
                        }
                    }
                }
            } catch (e: Exception) {
                android.util.Log.w("MiniPlayerView", "Play/pause action failed", e)
            }
        }

        binding.miniPreviousButton.setOnClickListener { view ->
            // Add visual feedback
            view.animate().scaleX(0.9f).scaleY(0.9f).setDuration(100)
                .withEndAction {
                    view.animate().scaleX(1.0f).scaleY(1.0f).setDuration(100).start()
                }.start()
            
            try {
                mediaController?.seekToPrevious() ?: musicPlayerManager?.skipToPrevious()
            } catch (e: Exception) {
                android.util.Log.w("MiniPlayerView", "Previous action failed", e)
            }
        }
        
        binding.miniNextButton.setOnClickListener { view ->
            // Add visual feedback
            view.animate().scaleX(0.9f).scaleY(0.9f).setDuration(100)
                .withEndAction {
                    view.animate().scaleX(1.0f).scaleY(1.0f).setDuration(100).start()
                }.start()
            
            try {
                mediaController?.seekToNext() ?: musicPlayerManager?.skipToNext()
            } catch (e: Exception) {
                android.util.Log.w("MiniPlayerView", "Next action failed", e)
            }
        }

        binding.miniFastForwardButton.setOnClickListener { view ->
            // Add visual feedback
            view.animate().scaleX(0.9f).scaleY(0.9f).setDuration(100)
                .withEndAction {
                    view.animate().scaleX(1.0f).scaleY(1.0f).setDuration(100).start()
                }.start()
            
            try {
                mediaController?.let { controller ->
                    val currentPos = controller.currentPosition
                    val duration = controller.duration
                    if (duration > 0) {
                        val newPos = (currentPos + 30000).coerceAtMost(duration)
                        controller.seekTo(newPos)
                        // Show visual feedback for seek
                        android.widget.Toast.makeText(context, "+30s", android.widget.Toast.LENGTH_SHORT).show()
                    }
                } ?: run {
                    // Fallback to player manager
                    musicPlayerManager?.let { manager ->
                        val currentPos = manager.currentPosition.value
                        val newPos = currentPos + 30000
                        manager.seekTo(newPos)
                        android.widget.Toast.makeText(context, "+30s", android.widget.Toast.LENGTH_SHORT).show()
                    }
                }
            } catch (e: Exception) {
                android.util.Log.w("MiniPlayerView", "Fast forward action failed", e)
            }
        }
        
        // Add rewind functionality to album artwork
        setupAlbumArtworkSeekGesture()
    }

    private fun connectToMediaController() {
        val sessionToken = SessionToken(context, ComponentName(context, MusicService::class.java))
        val controllerFuture = MediaController.Builder(context, sessionToken).buildAsync()
        
        controllerFuture.addListener({
            try {
                mediaController = controllerFuture.get()
                setupMediaControllerListeners()
                // Resync initial state so mini player shows even after process recreation
                resyncFromController()
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
                    show()
                } else {
                    // Keep visible when paused, only hide if idle with no item
                    stopProgressUpdates()
                    if (mediaController?.playbackState == Player.STATE_IDLE && mediaController?.currentMediaItem == null) hide() else show()
                }
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState != Player.STATE_IDLE || mediaController?.currentMediaItem != null) {
                    show()
                }
            }

            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                // Force UI update with retry mechanism
                post {
                    updateMediaInfo()
                    setArtworkFromMetadata()
                    if (mediaItem != null) {
                        show()
                        // Double-check after a short delay to ensure UI is updated
                        postDelayed({
                            if (mediaItem == mediaController?.currentMediaItem) {
                                updateMediaInfo()
                                setArtworkFromMetadata()
                            }
                        }, 200)
                    }
                }
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
                            // If we don't have a Song from manager, try controller state
                            if (mediaController?.currentMediaItem != null || mediaController?.playbackState == Player.STATE_READY) {
                                updateMediaInfo()
                                // Attempt to set artwork from cache using metadata
                                setArtworkFromMetadata()
                                show()
                            } else {
                                hide()
                            }
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
        
        // Check if spinning animation is enabled
        val appearancePrefs = AppearancePreferences.fromPrefs(context)
        updateSpinningAnimation(appearancePrefs.miniPlayerSpinningArt)
        
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

    private fun setArtworkFromMetadata() {
        try {
            val controller = mediaController ?: return
            val title = controller.mediaMetadata.title?.toString() ?: return
            val artist = controller.mediaMetadata.artist?.toString() ?: ""
            val album = controller.mediaMetadata.albumTitle?.toString() ?: ""
            
            val fakeSong = Song(
                id = 0L,
                title = title,
                artist = artist,
                album = album,
                duration = 0L,
                path = ""
            )
            
            val cache = com.stash.opusplayer.artwork.ArtworkCache(context)
            val bmp = cache.loadBitmapIfPresent(fakeSong, 256)
            
            if (bmp != null) {
                Glide.with(context)
                    .load(bmp)
                    .placeholder(R.drawable.ic_music_note)
                    .error(R.drawable.ic_music_note)
                    .centerCrop()
                    .into(binding.miniAlbumArt)
            } else {
                // Fallback to default artwork with subtle fade animation
                binding.miniAlbumArt.animate()
                    .alpha(0.7f)
                    .setDuration(200)
                    .withEndAction {
                        Glide.with(context)
                            .load(R.drawable.ic_music_note)
                            .into(binding.miniAlbumArt)
                        binding.miniAlbumArt.animate()
                            .alpha(1f)
                            .setDuration(200)
                            .start()
                    }
                    .start()
            }
        } catch (e: Exception) {
            // On any error, just show default artwork
            Glide.with(context)
                .load(R.drawable.ic_music_note)
                .into(binding.miniAlbumArt)
        }
    }

    fun resync() { resyncFromController() }

    private fun resyncFromController() {
        try {
            val controller = mediaController ?: return
            if (controller.currentMediaItem != null || controller.playbackState == Player.STATE_READY || controller.isPlaying) {
                updateMediaInfo()
                setArtworkFromMetadata()
                show()
            }
        } catch (_: Exception) {}
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

    private fun setupAlbumArtworkSeekGesture() {
        binding.miniAlbumArt.setOnTouchListener { view, event ->
            if (event.action == android.view.MotionEvent.ACTION_UP) {
                val viewWidth = view.width
                val touchX = event.x
                val leftHalf = viewWidth / 2f
                
                // Add ripple effect
                view.animate()
                    .scaleX(0.95f)
                    .scaleY(0.95f)
                    .setDuration(150)
                    .withEndAction {
                        view.animate()
                            .scaleX(1.0f)
                            .scaleY(1.0f)
                            .setDuration(150)
                            .start()
                    }
                    .start()
                
                try {
                    when {
                        touchX < leftHalf -> {
                            // Left side - seek backward 10 seconds
                            mediaController?.let { controller ->
                                val currentPos = controller.currentPosition
                                val newPos = (currentPos - 10000).coerceAtLeast(0)
                                controller.seekTo(newPos)
                            } ?: run {
                                musicPlayerManager?.let { manager ->
                                    val currentPos = manager.currentPosition.value
                                    val newPos = (currentPos - 10000).coerceAtLeast(0)
                                    manager.seekTo(newPos)
                                }
                            }
                            android.widget.Toast.makeText(context, "⏪ -10s", android.widget.Toast.LENGTH_SHORT).show()
                        }
                        else -> {
                            // Right side - seek forward 10 seconds
                            mediaController?.let { controller ->
                                val currentPos = controller.currentPosition
                                val duration = controller.duration
                                val newPos = (currentPos + 10000).coerceAtMost(if (duration > 0) duration else currentPos + 10000)
                                controller.seekTo(newPos)
                            } ?: run {
                                musicPlayerManager?.let { manager ->
                                    val currentPos = manager.currentPosition.value
                                    val newPos = currentPos + 10000
                                    manager.seekTo(newPos)
                                }
                            }
                            android.widget.Toast.makeText(context, "⏩ +10s", android.widget.Toast.LENGTH_SHORT).show()
                        }
                    }
                } catch (e: Exception) {
                    android.util.Log.w("MiniPlayerView", "Seek gesture failed", e)
                }
            }
            true // Consume the touch event
        }
    }

    /**
     * Apply appearance preferences to the mini player
     */
    fun applyAppearancePreferences(prefs: AppearancePreferences) {
        try {
            // Show/hide album art
            binding.miniAlbumArtCard.visibility = if (prefs.miniPlayerShowArt) VISIBLE else GONE
            
            // Show/hide artist name
            binding.miniArtistName.visibility = if (prefs.miniPlayerShowArtist) VISIBLE else GONE
            
            // Apply compact mode
            if (prefs.miniPlayerCompactMode) {
                val compactPadding = (4 * resources.displayMetrics.density).toInt()
                setPadding(compactPadding, compactPadding, compactPadding, compactPadding)
                binding.miniSongTitle.maxLines = 1
                binding.miniArtistName.maxLines = 1
            } else {
                val normalPadding = (8 * resources.displayMetrics.density).toInt()
                setPadding(normalPadding, normalPadding, normalPadding, normalPadding)
                binding.miniSongTitle.maxLines = 2
                binding.miniArtistName.maxLines = 1
            }
            
            // Apply colors
            setBackgroundColor(prefs.backgroundColor)
            binding.miniSongTitle.setTextColor(prefs.textPrimaryColor)
            binding.miniArtistName.setTextColor(prefs.textSecondaryColor)
            
            // Update spinning animation based on preference
            updateSpinningAnimation(prefs.miniPlayerSpinningArt && mediaController?.isPlaying == true)
            
        } catch (e: Exception) {
            android.util.Log.e("MiniPlayerView", "Error applying appearance preferences", e)
        }
    }

    fun release() {
        stopProgressUpdates()
        stopSpinningAnimation()
        mediaController?.release()
    }
    
    private fun updateSpinningAnimation(enabled: Boolean) {
        if (enabled && mediaController?.isPlaying == true) {
            startSpinningAnimation()
        } else {
            stopSpinningAnimation()
        }
    }
    
    private fun startSpinningAnimation() {
        stopSpinningAnimation()
        spinningAnimator = ObjectAnimator.ofFloat(binding.miniAlbumArt, "rotation", 0f, 360f).apply {
            duration = 10000 // 10 seconds for one full rotation
            repeatCount = ObjectAnimator.INFINITE
            interpolator = LinearInterpolator()
            start()
        }
    }
    
    private fun stopSpinningAnimation() {
        spinningAnimator?.cancel()
        spinningAnimator = null
        binding.miniAlbumArt.rotation = 0f
    }
}
