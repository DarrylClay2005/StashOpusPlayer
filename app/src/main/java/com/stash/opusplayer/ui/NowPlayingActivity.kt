package com.stash.stashwave.ui

import android.content.ComponentName
import android.content.Intent
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
import com.stash.stashwave.R
import com.stash.stashwave.audio.EqualizerManager
import com.stash.stashwave.data.Song
import com.stash.stashwave.databinding.ActivityNowPlayingBinding
import com.stash.stashwave.player.MusicPlayerManager
import com.stash.stashwave.service.MusicService
import androidx.core.os.bundleOf
import com.stash.stashwave.utils.MetadataExtractor
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
        
        // SynthWave visualization is passive; seeking remains via buttons/album art

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
                val enabled = !controller.shuffleModeEnabled
                controller.shuffleModeEnabled = enabled
                updateShuffleButton(enabled)
                // Show feedback to user
                val message = if (enabled) "Shuffle enabled" else "Shuffle disabled"
                android.widget.Toast.makeText(this, message, android.widget.Toast.LENGTH_SHORT).show()
                // Persist shuffle state
                try { getSharedPreferences("settings", 0).edit().putBoolean("playback_shuffle", enabled).apply() } catch (_: Exception) {}
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
                
                // Show feedback to user
                val message = when (nextMode) {
                    Player.REPEAT_MODE_OFF -> "Repeat off"
                    Player.REPEAT_MODE_ALL -> "Repeat all"
                    Player.REPEAT_MODE_ONE -> "Repeat one"
                    else -> "Repeat mode changed"
                }
                android.widget.Toast.makeText(this, message, android.widget.Toast.LENGTH_SHORT).show()
                
                // Persist repeat mode
                try { getSharedPreferences("settings", 0).edit().putInt("playback_repeat_mode", nextMode).apply() } catch (_: Exception) {}
            }
        }

        // Overflow menu (three dots)
        binding.menuButton.setOnClickListener { view ->
            val popup = android.widget.PopupMenu(this, view)
            popup.menuInflater.inflate(R.menu.now_playing_menu, popup.menu)
            popup.setOnMenuItemClickListener { item ->
                when (item.itemId) {
                    R.id.action_share -> {
                        shareCurrentTrack()
                        true
                    }
                    R.id.action_embed_artwork -> {
                        embedArtworkIntoFile()
                        true
                    }
                    else -> false
                }
            }
            popup.show()
        }
        
        // Seek bar (hidden) handlers retained for compatibility
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
                lifecycleScope.launch {
                    try {
val repository = com.stash.stashwave.data.MusicRepository(this@NowPlayingActivity)
                        val isFavorite = repository.isFavorite(song.id)
                        
                        if (isFavorite) {
                            repository.removeFromFavorites(song.id)
                            android.widget.Toast.makeText(this@NowPlayingActivity, "💔 Removed from favorites", android.widget.Toast.LENGTH_SHORT).show()
                        } else {
                            repository.addToFavorites(song)
                            android.widget.Toast.makeText(this@NowPlayingActivity, "❤️ Added to favorites", android.widget.Toast.LENGTH_SHORT).show()
                        }
                        
                        // Update UI
                        updateFavoriteButton(!isFavorite)
                        currentSong = song.copy(isFavorite = !isFavorite)
                        
                    } catch (e: Exception) {
                        android.util.Log.e("NowPlayingActivity", "Error toggling favorite", e)
                        android.widget.Toast.makeText(this@NowPlayingActivity, "Error updating favorites", android.widget.Toast.LENGTH_SHORT).show()
                    }
                }
            }
        }
        
        // Fast forward button (30 seconds)
        binding.fastForwardButton.setOnClickListener {
            mediaController?.let { controller ->
                val currentPos = controller.currentPosition
                val duration = controller.duration
                if (duration > 0) {
                    val newPos = (currentPos + 30000).coerceAtMost(duration)
                    controller.seekTo(newPos)
                    android.widget.Toast.makeText(this, "⏩ +30s", android.widget.Toast.LENGTH_SHORT).show()
                }
            }
        }
        
        // Add 10-second seek functionality to album artwork
        setupAlbumArtworkSeek()

        // Share button
        binding.shareButton.setOnClickListener { shareCurrentTrack() }

        // Audio controls have moved to Settings
    }
    
    private fun shareCurrentTrack() {
        val song = currentSong ?: return
        val text = "${song.displayName} — ${song.artistName}"
        try {
            val bitmap = metadataExtractor.loadCachedArtwork(this, song)
                ?: metadataExtractor.decodeAlbumArt(song.albumArt)
            if (bitmap != null) {
                val outDir = externalCacheDir?.let { java.io.File(it, "share") } ?: java.io.File(cacheDir, "share")
                if (!outDir.exists()) outDir.mkdirs()
                val outFile = java.io.File(outDir, "art_${System.currentTimeMillis()}.jpg")
                java.io.FileOutputStream(outFile).use { fos ->
                    bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 90, fos)
                }
                val uri = androidx.core.content.FileProvider.getUriForFile(
                    this,
                    "$packageName.fileprovider",
                    outFile
                )
                val intent = Intent(Intent.ACTION_SEND).apply {
                    type = "image/jpeg"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    putExtra(Intent.EXTRA_TEXT, text)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivity(Intent.createChooser(intent, "Share track"))
            } else {
                val intent = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, text)
                }
                startActivity(Intent.createChooser(intent, "Share track"))
            }
        } catch (_: Exception) {
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, text)
            }
            startActivity(Intent.createChooser(intent, "Share track"))
        }
    }

    private fun embedArtworkIntoFile() {
        val song = currentSong ?: return
        val path = song.path
        val ext = path.substringAfterLast('.', "").lowercase()
        // Get artwork bytes from cache or embedded field
        val artBitmap = metadataExtractor.loadCachedArtwork(this, song)
            ?: metadataExtractor.decodeAlbumArt(song.albumArt)
        if (artBitmap == null) {
            android.widget.Toast.makeText(this, "No artwork available to embed", android.widget.Toast.LENGTH_LONG).show()
            return
        }
        val baos = java.io.ByteArrayOutputStream()
        artBitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, baos)
        val jpegBytes = baos.toByteArray()
        
        lifecycleScope.launch(kotlinx.coroutines.Dispatchers.IO) {
            val ok = when (ext) {
"mp3" -> com.stash.stashwave.utils.TagEditor.embedArtworkMp3(this@NowPlayingActivity, path, jpegBytes)
else -> com.stash.stashwave.utils.TagEditor.embedArtworkAny(this@NowPlayingActivity, path, jpegBytes)
            }
            launch(kotlinx.coroutines.Dispatchers.Main) {
                if (ok) {
                    android.widget.Toast.makeText(this@NowPlayingActivity, "Artwork embedded", android.widget.Toast.LENGTH_SHORT).show()
                } else {
                    android.widget.Toast.makeText(this@NowPlayingActivity, "Failed to embed artwork", android.widget.Toast.LENGTH_LONG).show()
                }
            }
        }
    }

    private fun setupAlbumArtworkSeek() {
        binding.albumArtwork.setOnTouchListener { view, event ->
            if (event.action == android.view.MotionEvent.ACTION_UP) {
                val viewWidth = view.width
                val touchX = event.x
                val leftThird = viewWidth / 3f
                val rightThird = viewWidth * 2f / 3f
                
                mediaController?.let { controller ->
                    when {
                        touchX < leftThird -> {
                            // Left side - seek backward 10 seconds
                            val currentPos = controller.currentPosition
                            val newPos = (currentPos - 10000).coerceAtLeast(0)
                            controller.seekTo(newPos)
                            android.widget.Toast.makeText(this, "⏪ -10s", android.widget.Toast.LENGTH_SHORT).show()
                        }
                        touchX > rightThird -> {
                            // Right side - seek forward 10 seconds
                            val currentPos = controller.currentPosition
                            val duration = controller.duration
                            val newPos = (currentPos + 10000).coerceAtMost(duration)
                            controller.seekTo(newPos)
                            android.widget.Toast.makeText(this, "⏩ +10s", android.widget.Toast.LENGTH_SHORT).show()
                        }
                        // Middle third - do nothing (avoid accidental seeks)
                    }
                }
            }
            true // Consume the touch event
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
        
        // Visualization animates in real-time; no seeding needed

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
val fetcher = com.stash.stashwave.artwork.OnlineArtworkFetcher(this@NowPlayingActivity)
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
        
        // Auto-embed artwork into MP3 on first play if enabled and embedded art is missing
        tryAutoEmbedArtworkIfEnabled(song, cached, embedded)
        
        updateFavoriteButton(song.isFavorite)
    }
    
    private fun tryAutoEmbedArtworkIfEnabled(song: Song, cached: android.graphics.Bitmap?, embedded: android.graphics.Bitmap?) {
        try {
            val prefs = getSharedPreferences("settings", 0)
            if (!prefs.getBoolean("auto_embed_artwork", false)) return
            val ext = song.path.substringAfterLast('.', "").lowercase()
            val supported = setOf("mp3", "m4a", "mp4", "aac", "opus", "ogg")
            if (!supported.contains(ext)) return
            if (embedded != null) return // already embedded
            val art = cached ?: return
            val baos = java.io.ByteArrayOutputStream()
            art.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, baos)
            val jpeg = baos.toByteArray()
            lifecycleScope.launch(kotlinx.coroutines.Dispatchers.IO) {
                if (ext == "mp3") {
                    com.stash.stashwave.utils.TagEditor.embedArtworkMp3(this@NowPlayingActivity, song.path, jpeg)
                } else {
                    com.stash.stashwave.utils.TagEditor.embedArtworkAny(this@NowPlayingActivity, song.path, jpeg)
                }
            }
        } catch (_: Exception) {}
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
            try { binding.seekBar.max = duration.toInt() } catch (_: Exception) {}
            try { binding.seekBar.progress = currentPosition.toInt() } catch (_: Exception) {}
            // Visualization does not need explicit progress updates
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
