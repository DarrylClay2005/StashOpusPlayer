package com.stash.opusplayer.ui

import android.content.Intent
import android.content.pm.ActivityInfo
import android.os.Bundle
import android.os.Build
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.SeekBar
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.lifecycleScope
import com.pierfrancescosoffritti.androidyoutubeplayer.core.player.YouTubePlayer
import com.pierfrancescosoffritti.androidyoutubeplayer.core.player.listeners.AbstractYouTubePlayerListener
import com.pierfrancescosoffritti.androidyoutubeplayer.core.player.options.IFramePlayerOptions
import com.pierfrancescosoffritti.androidyoutubeplayer.core.player.utils.loadOrCueVideo
import com.stash.opusplayer.R
import com.stash.opusplayer.databinding.ActivityYoutubeStreamingBinding
import com.stash.opusplayer.data.YouTubeVideo
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class YouTubeStreamingActivity : AppCompatActivity() {

    private lateinit var binding: ActivityYoutubeStreamingBinding
    private var youTubePlayer: YouTubePlayer? = null
    private lateinit var ytPrefs: android.content.SharedPreferences
private lateinit var commentsAdapter: com.stash.opusplayer.ui.adapters.YouTubeCommentsAdapter
    private var commentsNextPageToken: String? = null
    private var commentsOrder: String = "relevance"
private val commentsAll = mutableListOf<com.stash.opusplayer.data.YouTubeComment>()
    private val expandedParents = mutableSetOf<String>()
private val youTubeApiService by lazy { com.stash.opusplayer.network.YouTubeApiService(this) }
    private var isPlaying = false
    private var currentTime = 0f
    private var duration = 0f
    private var currentVideo: YouTubeVideo? = null
    private var isLoading = false
    private var isFullscreen = false

    // Track original parent and layout for fullscreen swaps
    private var originalPlayerParent: ViewGroup? = null
    private var originalPlayerIndex: Int = -1
    private var originalPlayerLayoutParams: ViewGroup.LayoutParams? = null
    
    // Playback speed state (no pitch/effects for YouTube)
    private var currentSpeed: Float = 1.0f
    
    companion object {
        private const val TAG = "YouTubeStreamingActivity"
        const val EXTRA_VIDEO = "extra_video"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityYoutubeStreamingBinding.inflate(layoutInflater)
        setContentView(binding.root)

        ytPrefs = getSharedPreferences("youtube_prefs", MODE_PRIVATE)

        // Get video from intent
        val video: YouTubeVideo? = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(EXTRA_VIDEO, YouTubeVideo::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra<YouTubeVideo>(EXTRA_VIDEO)
        }

        video?.let {
            currentVideo = it
            displayVideoInfo(it)
            restorePerVideoSettings(it)
            setupYouTubePlayer(it)
        } ?: run {
            Toast.makeText(this, "No video data provided", Toast.LENGTH_SHORT).show()
            finish()
            return
        }

        setupControls()
        setupCommentsUI()
        loadComments()
    }


    private fun setupYouTubePlayer(video: YouTubeVideo) {
        lifecycle.addObserver(binding.youtubePlayerView)

        val iFramePlayerOptions = IFramePlayerOptions.Builder()
            .controls(0) // Hide YouTube controls
            .rel(0) // Don't show related videos
            .ivLoadPolicy(3) // Don't show annotations
            .ccLoadPolicy(0) // Don't show captions by default
            .build()

        binding.youtubePlayerView.enableAutomaticInitialization = false

        binding.youtubePlayerView.initialize(object : AbstractYouTubePlayerListener() {
            override fun onReady(youTubePlayer: YouTubePlayer) {
                this@YouTubeStreamingActivity.youTubePlayer = youTubePlayer
                
                youTubePlayer.loadOrCueVideo(lifecycle, video.id, 0f)
            }

            override fun onStateChange(
                youTubePlayer: YouTubePlayer, 
                state: com.pierfrancescosoffritti.androidyoutubeplayer.core.player.PlayerConstants.PlayerState
            ) {
                when (state) {
                    com.pierfrancescosoffritti.androidyoutubeplayer.core.player.PlayerConstants.PlayerState.PLAYING -> {
                        isPlaying = true
                        isLoading = false
                        binding.playPauseButton.setImageResource(R.drawable.ic_pause_24)
                        startTimeTracking()
                    }
                    com.pierfrancescosoffritti.androidyoutubeplayer.core.player.PlayerConstants.PlayerState.PAUSED -> {
                        isPlaying = false
                        binding.playPauseButton.setImageResource(R.drawable.ic_play_arrow_24)
                    }
                    com.pierfrancescosoffritti.androidyoutubeplayer.core.player.PlayerConstants.PlayerState.ENDED -> {
                        isPlaying = false
                        binding.playPauseButton.setImageResource(R.drawable.ic_play_arrow_24)
                        currentTime = 0f
                        updateProgressBar()
                    }
                    com.pierfrancescosoffritti.androidyoutubeplayer.core.player.PlayerConstants.PlayerState.BUFFERING -> {
                        isLoading = true
                        Toast.makeText(this@YouTubeStreamingActivity, "Buffering...", Toast.LENGTH_SHORT).show()
                    }
                    com.pierfrancescosoffritti.androidyoutubeplayer.core.player.PlayerConstants.PlayerState.UNSTARTED -> {
                        isLoading = true
                    }
                    else -> {}
                }
            }
            
            override fun onError(
                youTubePlayer: YouTubePlayer,
                error: com.pierfrancescosoffritti.androidyoutubeplayer.core.player.PlayerConstants.PlayerError
            ) {
                Log.e(TAG, "YouTube Player Error: $error")
                Toast.makeText(this@YouTubeStreamingActivity, "Video playback error: $error", Toast.LENGTH_LONG).show()
                isLoading = false
            }

            override fun onCurrentSecond(youTubePlayer: YouTubePlayer, second: Float) {
                currentTime = second
                updateProgressBar()
            }

            override fun onVideoDuration(youTubePlayer: YouTubePlayer, duration: Float) {
                this@YouTubeStreamingActivity.duration = duration
                binding.progressBar.max = duration.toInt()
                binding.totalTime.text = formatTime(duration)
            }
        }, iFramePlayerOptions)
    }

    private fun displayVideoInfo(video: YouTubeVideo) {
        binding.videoTitle.text = video.title
        binding.channelTitle.text = video.channelTitle
        binding.videoDescription.text = video.description.take(200) + if (video.description.length > 200) "..." else ""
        
        // Load thumbnail using Glide
        try {
            val thumbnailUrl = if (video.highResThumbnailUrl?.isNotEmpty() == true) {
                video.highResThumbnailUrl
            } else {
                video.thumbnailUrl
            }
            
            com.bumptech.glide.Glide.with(this)
                .load(thumbnailUrl)
                .placeholder(R.drawable.ic_music_note)
                .error(R.drawable.ic_music_note)
                .into(binding.videoThumbnail)
        } catch (e: Exception) {
            Log.w(TAG, "Error loading thumbnail", e)
        }
    }

    private fun setupControls() {
        // Background play button
        binding.backgroundPlayButton.setOnClickListener {
            startBackgroundAudio()
        }
        // Back button
        binding.backButton.setOnClickListener {
            finish()
        }

        // Play/Pause button
        binding.playPauseButton.setOnClickListener {
            youTubePlayer?.let { player ->
                if (isPlaying) {
                    player.pause()
                } else {
                    player.play()
                }
            }
        }

        // Progress bar
        binding.progressBar.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                if (fromUser) {
                    binding.currentTime.text = formatTime(progress.toFloat())
                }
            }

            override fun onStartTrackingTouch(seekBar: SeekBar?) {}

            override fun onStopTrackingTouch(seekBar: SeekBar?) {
                seekBar?.let {
                    youTubePlayer?.seekTo(it.progress.toFloat())
                }
            }
        })

        // Speed controls
        binding.speedButton.setOnClickListener {
            showSpeedDialog()
        }

        // Fullscreen button
        binding.fullscreenButton.setOnClickListener {
            toggleFullscreen()
        }

        // Quality button
        binding.qualityButton.setOnClickListener {
            showQualityDialog()
        }

        // Seek buttons (+/- 10s)
        binding.seekBackwardButton.setOnClickListener {
            youTubePlayer?.let { player ->
                val newTime = (currentTime - 10f).coerceAtLeast(0f)
                player.seekTo(newTime)
                Toast.makeText(this, "⏪ -10s", Toast.LENGTH_SHORT).show()
            }
        }
        binding.seekForwardButton.setOnClickListener {
            youTubePlayer?.let { player ->
                val newTime = (currentTime + 10f).coerceAtMost(duration)
                player.seekTo(newTime)
                Toast.makeText(this, "⏩ +10s", Toast.LENGTH_SHORT).show()
            }
        }
    }



    private fun showSpeedDialog() {
        val speeds = arrayOf("0.5x", "1x", "1.5x", "2x")
        val speedValues = arrayOf(0.5f, 1.0f, 1.5f, 2.0f)
        
        // Find current speed index
        val currentIndex = speedValues.indexOfFirst { kotlin.math.abs(it - currentSpeed) < 0.01f }
        
        androidx.appcompat.app.AlertDialog.Builder(this)
            .setTitle("Playback Speed")
            .setSingleChoiceItems(speeds, currentIndex) { dialog, which ->
                currentSpeed = speedValues[which]
                binding.speedButton.text = speeds[which]
                
                // Persist per-video speed
                currentVideo?.let { v -> ytPrefs.edit().putFloat("speed_${v.id}", currentSpeed).apply() }

                // Apply speed through playback rate
                youTubePlayer?.setPlaybackRate(mapSpeedToPlaybackRate(currentSpeed))
                Toast.makeText(this, "Speed: ${speeds[which]}", Toast.LENGTH_SHORT).show()
                dialog.dismiss()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }


    private fun showQualityDialog() {
        val qualities = arrayOf("Auto", "144p", "240p", "360p", "480p", "720p", "1080p")
        
        androidx.appcompat.app.AlertDialog.Builder(this)
            .setTitle("Video Quality")
            .setItems(qualities) { _, which ->
                // Note: YouTube Player API doesn't allow direct quality control
                // This is mainly for UI completeness
                binding.qualityButton.text = qualities[which]
                Toast.makeText(this, "Quality: ${qualities[which]}", Toast.LENGTH_SHORT).show()
            }
            .show()
    }

    private fun toggleFullscreen() {
        val playerView = binding.youtubePlayerView
        if (isFullscreen) {
            // Exit fullscreen: restore view to original parent
            isFullscreen = false
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            binding.controlsContainer.visibility = View.VISIBLE
            binding.fullscreenButton.setImageResource(R.drawable.ic_fullscreen_24)

            // Move player back to its original container
            try {
                val container = binding.fullscreenContainer
                container.visibility = View.GONE
                container.removeView(playerView)
                val parent = originalPlayerParent
                val index = originalPlayerIndex
                val lp = originalPlayerLayoutParams
                if (parent != null && index >= 0 && lp != null) {
                    parent.addView(playerView, index, lp)
                } else if (parent != null) {
                    parent.addView(playerView)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed restoring player view: ${e.message}")
            }

            // Reset cutout mode
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val lp = window.attributes
                lp.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_NEVER
                window.attributes = lp
            }
            showSystemBars()
            supportActionBar?.show()
        } else {
            // Enter fullscreen: move view into overlay container
            isFullscreen = true
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            binding.controlsContainer.visibility = View.GONE
            binding.fullscreenButton.setImageResource(R.drawable.ic_fullscreen_exit_24)

            try {
                val parent = playerView.parent as? ViewGroup
                if (parent != null) {
                    originalPlayerParent = parent
                    originalPlayerIndex = parent.indexOfChild(playerView)
                    originalPlayerLayoutParams = playerView.layoutParams
                    parent.removeView(playerView)
                }
                val container = binding.fullscreenContainer
                container.visibility = View.VISIBLE
                container.addView(
                    playerView,
                    ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                )
            } catch (e: Exception) {
                Log.w(TAG, "Failed entering fullscreen: ${e.message}")
            }

            // Enable drawing into display cutouts on short edges when fullscreen
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val lp = window.attributes
                lp.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                window.attributes = lp
            }
            hideSystemBars()
            supportActionBar?.hide()
        }
        Toast.makeText(this, if (isFullscreen) "Fullscreen ON" else "Fullscreen OFF", Toast.LENGTH_SHORT).show()
    }

    private fun mapSpeedToPlaybackRate(speed: Float): com.pierfrancescosoffritti.androidyoutubeplayer.core.player.PlayerConstants.PlaybackRate {
        return when {
            speed <= 0.6f -> com.pierfrancescosoffritti.androidyoutubeplayer.core.player.PlayerConstants.PlaybackRate.RATE_0_5
            speed <= 1.1f -> com.pierfrancescosoffritti.androidyoutubeplayer.core.player.PlayerConstants.PlaybackRate.RATE_1
            speed <= 1.6f -> com.pierfrancescosoffritti.androidyoutubeplayer.core.player.PlayerConstants.PlaybackRate.RATE_1_5
            else -> com.pierfrancescosoffritti.androidyoutubeplayer.core.player.PlayerConstants.PlaybackRate.RATE_2
        }
    }

    private fun restorePerVideoSettings(video: YouTubeVideo) {
        try {
            // Restore speed
            val savedSpeed = ytPrefs.getFloat("speed_${video.id}", 1.0f)
            currentSpeed = savedSpeed
            binding.speedButton.text = when (savedSpeed) {
                0.5f -> "0.5x"
                1.5f -> "1.5x"
                2.0f -> "2x"
                else -> "1x"
            }
            // Apply playback rate if player already ready later
            youTubePlayer?.setPlaybackRate(mapSpeedToPlaybackRate(currentSpeed))

            // No per-video pitch/effects for YouTube
        } catch (_: Exception) {}
    }

    private fun setupCommentsUI() {
commentsAdapter = com.stash.opusplayer.ui.adapters.YouTubeCommentsAdapter(
            onViewReplies = { comment ->
                comment.commentId?.let { showRepliesDialog(it) }
            }
        )
        binding.commentsRecycler.apply {
            adapter = commentsAdapter
            layoutManager = androidx.recyclerview.widget.LinearLayoutManager(this@YouTubeStreamingActivity)
            isNestedScrollingEnabled = false
        }
        
        binding.commentsOrderButton.setOnClickListener {
            val options = arrayOf("Top", "Newest")
            androidx.appcompat.app.AlertDialog.Builder(this)
                .setTitle("Sort comments by")
                .setSingleChoiceItems(options, if (commentsOrder == "relevance") 0 else 1) { dialog, which ->
                    commentsOrder = if (which == 0) "relevance" else "time"
                    binding.commentsOrderButton.text = if (which == 0) "Top" else "Newest"
                    commentsNextPageToken = null
                    commentsAll.clear()
                    commentsAdapter.submitList(emptyList())
                    com.google.android.material.snackbar.Snackbar.make(binding.root, "Sorting by ${if (which==0) "Top" else "Newest"}", com.google.android.material.snackbar.Snackbar.LENGTH_SHORT).show()
                    loadComments(null)
                    dialog.dismiss()
                }
                .setNegativeButton("Cancel", null)
                .show()
        }

        binding.commentsLoadMoreButton.setOnClickListener {
            val next = commentsNextPageToken
            if (!next.isNullOrBlank()) loadComments(next)
        }

        // Inline replies expansion/collapse
        // Handled via adapter callback and showRepliesDialog replacement below
    }

    private fun showRepliesDialog(parentId: String) {
        // Deprecated: now using inline expansion
        inlineToggleReplies(parentId)
    }

    private fun inlineToggleReplies(parentId: String) {
        val index = commentsAll.indexOfFirst { it.commentId == parentId }
        if (index == -1) return
        if (expandedParents.contains(parentId)) {
            // Collapse: remove children
            val toRemove = commentsAll.filter { it.parentId == parentId }
            commentsAll.removeAll(toRemove)
            commentsAdapter.submitList(commentsAll.toList())
            expandedParents.remove(parentId)
            return
        }
        // Expand: fetch and insert
        binding.commentsProgressContainer.visibility = View.VISIBLE
        binding.commentsProgressText.text = "Loading replies…"
        lifecycleScope.launch {
            try {
                val res = youTubeApiService.getCommentReplies(parentId)
                res.onSuccess { result ->
                    binding.commentsProgressContainer.visibility = View.GONE
                    if (result.comments.isNotEmpty()) {
                        commentsAll.addAll(index + 1, result.comments)
                        commentsAdapter.submitList(commentsAll.toList())
                        expandedParents.add(parentId)
                    } else {
                        com.google.android.material.snackbar.Snackbar.make(binding.root, "No replies", com.google.android.material.snackbar.Snackbar.LENGTH_SHORT).show()
                    }
                }
                res.onFailure { e ->
                    binding.commentsProgressContainer.visibility = View.GONE
                    com.google.android.material.snackbar.Snackbar.make(binding.root, "Failed to load replies: ${e.message}", com.google.android.material.snackbar.Snackbar.LENGTH_SHORT).show()
                }
            } catch (e: Exception) {
                binding.commentsProgressContainer.visibility = View.GONE
                com.google.android.material.snackbar.Snackbar.make(binding.root, "Failed to load replies: ${e.message}", com.google.android.material.snackbar.Snackbar.LENGTH_SHORT).show()
            }
        }
    }

    private fun loadComments(pageToken: String? = null) {
        val videoId = currentVideo?.id ?: return
        // Check cache on first page
        if (pageToken == null) {
com.stash.opusplayer.utils.YouTubeCommentsCache.get(videoId, commentsOrder)?.let { entry ->
                commentsAll.clear()
                commentsAll.addAll(entry.comments)
                commentsAdapter.submitList(commentsAll.toList())
                commentsNextPageToken = entry.nextPageToken
                binding.commentsLoadMoreButton.visibility = if (commentsNextPageToken.isNullOrBlank()) View.GONE else View.VISIBLE
                return
            }
        }

        // Show progress
        binding.commentsProgressContainer.visibility = View.VISIBLE
        binding.commentsProgressText.text = "Loading comments…"
        lifecycleScope.launch {
            try {
                val result = youTubeApiService.getComments(videoId, maxResults = 20, pageToken = pageToken, order = commentsOrder)
                result.onSuccess { res ->
                    binding.commentsProgressContainer.visibility = View.GONE
                    commentsNextPageToken = res.nextPageToken
                    if (pageToken == null) commentsAll.clear()
                    if (res.comments.isNotEmpty()) {
                        commentsAll.addAll(res.comments)
                        commentsAdapter.submitList(commentsAll.toList())
                        if (pageToken == null) {
                            com.stash.opusplayer.utils.YouTubeCommentsCache.put(videoId, commentsOrder,
                                com.stash.opusplayer.utils.YouTubeCommentsCache.Entry(commentsAll.toList(), res.nextPageToken))
                        }
                    } else if (commentsAll.isEmpty()) {
                        binding.commentsProgressContainer.visibility = View.VISIBLE
                        binding.commentsProgressText.text = "No comments"
                    }
                    binding.commentsLoadMoreButton.visibility = if (commentsNextPageToken.isNullOrBlank()) View.GONE else View.VISIBLE
                }
                result.onFailure { e ->
                    binding.commentsProgressContainer.visibility = View.VISIBLE
                    binding.commentsProgressText.text = "Failed to load comments: ${e.message}"
                }
            } catch (e: Exception) {
                binding.commentsProgressContainer.visibility = View.VISIBLE
                binding.commentsProgressText.text = "Failed to load comments: ${e.message}"
            }
        }
    }

    private fun startTimeTracking() {
        lifecycleScope.launch {
            while (isPlaying) {
                delay(1000)
                updateProgressBar()
            }
        }
    }

    private fun updateProgressBar() {
        runOnUiThread {
            binding.progressBar.progress = currentTime.toInt()
            binding.currentTime.text = formatTime(currentTime)
        }
    }

    private fun startBackgroundAudio() {
        val video = currentVideo ?: return
        // Resolve stream URL with yt-dlp and hand off to our Media3 MusicService for background playback
        lifecycleScope.launch {
            try {
                binding.playPauseButton.isEnabled = false
                Toast.makeText(this@YouTubeStreamingActivity, "Preparing background audio…", Toast.LENGTH_SHORT).show()
val extractor = com.stash.opusplayer.utils.YtDlpExtractor(this@YouTubeStreamingActivity)
                val url = extractor.getBestAudioStreamUrl(video.formattedUrl)
                if (url.isNullOrBlank()) {
                    // Prefetch thumbnail into cache before delegating to Seal
                    try {
                        val meta = com.stash.opusplayer.utils.MetadataExtractor(this@YouTubeStreamingActivity)
                        val b64 = meta.downloadYouTubeThumbnail(video.id)
                        if (b64 != null) {
                            val bytes = android.util.Base64.decode(b64, android.util.Base64.DEFAULT)
                            val cache = com.stash.opusplayer.artwork.ArtworkCache(this@YouTubeStreamingActivity)
                            val variants = listOf(
                                com.stash.opusplayer.data.Song(0L, video.title, video.channelTitle, "YouTube", 0L, ""),
                                com.stash.opusplayer.data.Song(0L, video.title, video.channelTitle, "Unknown Album", 0L, ""),
                                com.stash.opusplayer.data.Song(0L, video.title, video.channelTitle, "", 0L, ""),
                                com.stash.opusplayer.data.Song(0L, video.title, "Unknown Artist", "YouTube", 0L, ""),
                                com.stash.opusplayer.data.Song(0L, video.title, "Unknown Artist", "Unknown Album", 0L, ""),
                                com.stash.opusplayer.data.Song(0L, video.title, "Unknown Artist", "", 0L, "")
                            )
                            variants.forEach { s ->
                                val f = cache.fileFor(s)
                                if (!f.exists()) cache.saveJpeg(bytes, f)
                            }
                            // Also save by title-only key
                            val tf = cache.fileForTitleOnly(video.title)
                            if (!tf.exists()) cache.saveJpeg(bytes, tf)
                        }
                    } catch (_: Exception) {}

// Fallback: if Seal is installed, open there so user can use background playback
val opened = com.stash.opusplayer.integration.SealIntegration.openInSeal(this@YouTubeStreamingActivity, video.formattedUrl)
                    if (!opened) {
                        Toast.makeText(this@YouTubeStreamingActivity, "Unable to resolve audio stream", Toast.LENGTH_LONG).show()
                    } else {
                        Toast.makeText(this@YouTubeStreamingActivity, "Open in Seal for background playback", Toast.LENGTH_LONG).show()
                    }
                    binding.playPauseButton.isEnabled = true
                    return@launch
                }
                // Build media metadata
                val meta = androidx.media3.common.MediaMetadata.Builder()
                    .setTitle(video.title)
                    .setArtist(video.channelTitle)
                    .build()
                val item = androidx.media3.common.MediaItem.Builder()
                    .setUri(android.net.Uri.parse(url))
                    .setMediaMetadata(meta)
                    .build()

                val token = androidx.media3.session.SessionToken(this@YouTubeStreamingActivity, android.content.ComponentName(this@YouTubeStreamingActivity, com.stash.opusplayer.service.MusicService::class.java))
                val future = androidx.media3.session.MediaController.Builder(this@YouTubeStreamingActivity, token).buildAsync()
                future.addListener({
                    try {
                        val controller = future.get()
                        controller.setMediaItem(item)
                        controller.prepare()
                        controller.play()
                        // Pause the embedded YouTube player and inform user
                        youTubePlayer?.pause()
                        Toast.makeText(this@YouTubeStreamingActivity, "Playing in background", Toast.LENGTH_SHORT).show()
                        // Optionally finish activity to get out of the way
                        // finish()
                    } catch (e: Exception) {
                        Toast.makeText(this@YouTubeStreamingActivity, "Failed to start background playback: ${e.message}", Toast.LENGTH_LONG).show()
                    } finally {
                        binding.playPauseButton.isEnabled = true
                    }
                }, com.google.common.util.concurrent.MoreExecutors.directExecutor())
            } catch (e: Exception) {
                Toast.makeText(this@YouTubeStreamingActivity, "Error: ${e.message}", Toast.LENGTH_LONG).show()
                binding.playPauseButton.isEnabled = true
            }
        }
    }

    private fun formatTime(seconds: Float): String {
        val minutes = (seconds / 60).toInt()
        val secs = (seconds % 60).toInt()
        return String.format("%d:%02d", minutes, secs)
    }

    private fun hideSystemBars() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        val controller = WindowInsetsControllerCompat(window, window.decorView)
        controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        controller.hide(WindowInsetsCompat.Type.systemBars())
    }

    private fun showSystemBars() {
        val controller = WindowInsetsControllerCompat(window, window.decorView)
        controller.show(WindowInsetsCompat.Type.systemBars())
        WindowCompat.setDecorFitsSystemWindows(window, true)
    }

    override fun onBackPressed() {
        if (isFullscreen) {
            toggleFullscreen()
            return
        }
        super.onBackPressed()
    }

    override fun onDestroy() {
        youTubePlayer?.let {
            binding.youtubePlayerView.release()
        }
        super.onDestroy()
    }
}
