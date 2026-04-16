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
import com.stash.opusplayer.utils.AnimationUtils
import kotlinx.coroutines.launch
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.VelocityTracker
import android.animation.ValueAnimator
import android.animation.AnimatorSet
import android.graphics.*
import android.media.AudioManager
import android.view.View
import kotlin.math.*
import kotlin.random.Random
import android.animation.AnimatorListenerAdapter
import android.animation.Animator
import com.stash.opusplayer.ui.appearance.ThemeManager
import kotlin.math.roundToInt

class MiniPlayerView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : FrameLayout(context, attrs, defStyleAttr), MiniPlayerSurface {

    private val binding: MiniPlayerBinding
    private var mediaController: MediaController? = null
    private var musicPlayerManager: MusicPlayerManager? = null
    private val metadataExtractor = MetadataExtractor(context)
    
    private val progressHandler = Handler(Looper.getMainLooper())
    private var progressRunnable: Runnable? = null
    
    private var currentSong: Song? = null
    private var lifecycleOwner: LifecycleOwner? = null
    private var spinningAnimator: ObjectAnimator? = null
    
    // Enhanced gesture controls
    private lateinit var gestureDetector: GestureDetector
    private var velocityTracker: VelocityTracker? = null
    private val audioManager by lazy { context.getSystemService(Context.AUDIO_SERVICE) as AudioManager }
    
    // Mini visualizer
    private var miniVisualizerAnimator: ValueAnimator? = null
    private var audioData: FloatArray = FloatArray(16) { Random.nextFloat() }
    private val miniVisualizerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        shader = LinearGradient(
            0f, 0f, 0f, 20f,
            Color.parseColor("#FF00FF"),
            Color.parseColor("#00FFFF"),
            Shader.TileMode.CLAMP
        )
    }
    
    // Progress ring
    private val progressRingPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 6f
        color = Color.parseColor("#FF00FF")
        strokeCap = Paint.Cap.ROUND
    }
    
    // Album art carousel
    private var queuePosition = 0
    private var carouselOffset = 0f
    private var carouselAnimator: ValueAnimator? = null

    init {
        binding = MiniPlayerBinding.inflate(LayoutInflater.from(context), this, true)
        setupEnhancedGestureSystem()
        setupUI()
        startMiniVisualizer()
        visibility = GONE // Initially hidden
    }

    override fun initialize(lifecycleOwner: LifecycleOwner, musicPlayerManager: MusicPlayerManager) {
        this.lifecycleOwner = lifecycleOwner
        this.musicPlayerManager = musicPlayerManager
        
        connectToMediaController()
        observePlayerState()
    }
    
    /**
     * Enhanced gesture system for advanced mini player controls
     */
    private fun setupEnhancedGestureSystem() {
        gestureDetector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
            override fun onFling(e1: MotionEvent?, e2: MotionEvent, velocityX: Float, velocityY: Float): Boolean {
                if (e1 == null || e2 == null) return false
                
                val deltaX = e2.x - e1.x
                val deltaY = e2.y - e1.y
                
                // Determine if it's a horizontal or vertical swipe
                if (abs(deltaX) > abs(deltaY)) {
                    // Horizontal swipe - track control
                    if (abs(deltaX) > 100 && abs(velocityX) > 500) {
                        if (deltaX > 0) {
                            // Swipe right - next track
                            handleNextTrack()
                            animateSwipeGesture("Next Track ⏭️")
                        } else {
                            // Swipe left - previous track
                            handlePreviousTrack()
                            animateSwipeGesture("Previous Track ⏮️")
                        }
                        return true
                    }
                } else {
                    // Vertical swipe - volume control
                    if (abs(deltaY) > 80 && abs(velocityY) > 400) {
                        if (deltaY < 0) {
                            // Swipe up - volume up
                            adjustVolume(true)
                            animateSwipeGesture("Volume Up 🔊")
                        } else {
                            // Swipe down - volume down
                            adjustVolume(false)
                            animateSwipeGesture("Volume Down 🔉")
                        }
                        return true
                    }
                }
                return false
            }
            
            override fun onDoubleTap(e: MotionEvent): Boolean {
                // Double tap - play/pause
                handlePlayPause()
                animateDoubleTap()
                return true
            }
            
            override fun onLongPress(e: MotionEvent) {
                // Long press - show queue or options
                showQueuePreview()
            }
        })
        
        // Set up touch handling for the entire mini player
        setOnTouchListener { _, event ->
            velocityTracker = velocityTracker ?: VelocityTracker.obtain()
            velocityTracker?.addMovement(event)
            
            when (event.action) {
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    velocityTracker?.recycle()
                    velocityTracker = null
                }
            }
            
            gestureDetector.onTouchEvent(event)
        }
        
        // Enable focus for gesture detection
        isFocusable = true
        isFocusableInTouchMode = true
    }
    
    private fun handleNextTrack() {
        try {
            mediaController?.seekToNext() ?: musicPlayerManager?.skipToNext()
        } catch (e: Exception) {
            android.util.Log.w("MiniPlayerView", "Next track failed", e)
        }
    }
    
    private fun handlePreviousTrack() {
        try {
            mediaController?.seekToPrevious() ?: musicPlayerManager?.skipToPrevious()
        } catch (e: Exception) {
            android.util.Log.w("MiniPlayerView", "Previous track failed", e)
        }
    }
    
    private fun handlePlayPause() {
        try {
            mediaController?.let { controller ->
                if (controller.isPlaying) {
                    controller.pause()
                } else {
                    controller.play()
                }
            } ?: run {
                musicPlayerManager?.let { manager ->
                    if (manager.isPlaying.value) {
                        manager.pause()
                    } else {
                        manager.play()
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.w("MiniPlayerView", "Play/pause failed", e)
        }
    }
    
    private fun adjustVolume(increase: Boolean) {
        try {
            if (increase) {
                audioManager.adjustStreamVolume(
                    AudioManager.STREAM_MUSIC,
                    AudioManager.ADJUST_RAISE,
                    AudioManager.FLAG_SHOW_UI
                )
            } else {
                audioManager.adjustStreamVolume(
                    AudioManager.STREAM_MUSIC,
                    AudioManager.ADJUST_LOWER,
                    AudioManager.FLAG_SHOW_UI
                )
            }
        } catch (e: Exception) {
            android.util.Log.w("MiniPlayerView", "Volume adjustment failed", e)
        }
    }
    
    private fun animateSwipeGesture(message: String) {
        // Create a ripple effect from the gesture
        animate()
            .scaleX(1.05f)
            .scaleY(1.05f)
            .setDuration(150)
            .withEndAction {
                animate()
                    .scaleX(1f)
                    .scaleY(1f)
                    .setDuration(150)
                    .start()
            }
            .start()
        
        showVisualFeedbackViaParent(message)
    }
    
    private fun animateDoubleTap() {
        // Pulsing animation for double tap
        val pulseAnimator = ValueAnimator.ofFloat(1f, 1.2f, 1f).apply {
            duration = 300
            addUpdateListener { animation ->
                val scale = animation.animatedValue as Float
                binding.miniPlayPauseButton.scaleX = scale
                binding.miniPlayPauseButton.scaleY = scale
            }
        }
        pulseAnimator.start()
    }
    
    private fun showQueuePreview() {
        // Show a preview of the queue or additional options
        showVisualFeedbackViaParent("Queue: ${getQueueInfo()}")
        
        // Optional: Navigate to queue or show popup
        // This could be expanded to show a mini queue preview
    }
    
    private fun getQueueInfo(): String {
        return try {
            val playlist = musicPlayerManager?.playlist?.value
            if (playlist != null && playlist.isNotEmpty()) {
                "${playlist.size} tracks"
            } else {
                "Empty"
            }
        } catch (e: Exception) {
            "Unknown"
        }
    }
    
    /**
     * Mini visualizer for the collapsed mini player
     */
    private fun startMiniVisualizer() {
        miniVisualizerAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 100
            repeatCount = ValueAnimator.INFINITE
            addUpdateListener {
                // Generate fake audio data for visualization
                for (i in audioData.indices) {
                    audioData[i] = (audioData[i] * 0.8f + Random.nextFloat() * 0.2f).coerceIn(0f, 1f)
                }
                
                // Update progress bar if available
                invalidate()
            }
        }
    }
    
    private fun stopMiniVisualizer() {
        miniVisualizerAnimator?.cancel()
        miniVisualizerAnimator = null
    }
    
    /**
     * Custom drawing for progress ring around album art
     */
    override fun dispatchDraw(canvas: Canvas) {
        super.dispatchDraw(canvas)
        
        // Draw progress ring around album art
        drawProgressRing(canvas)
        
        // Draw mini visualizer on progress bar
        if (mediaController?.isPlaying == true) {
            drawMiniVisualizer(canvas)
        }
    }
    
    private fun drawProgressRing(canvas: Canvas) {
        try {
            val albumArt = binding.miniAlbumArt
            val centerX = albumArt.x + albumArt.width / 2f
            val centerY = albumArt.y + albumArt.height / 2f
            val radius = max(albumArt.width, albumArt.height) / 2f + 8f
            
            // Get current progress
            val progress = mediaController?.let { controller ->
                if (controller.duration > 0) {
                    controller.currentPosition.toFloat() / controller.duration.toFloat()
                } else 0f
            } ?: 0f
            
            // Draw background circle
            val backgroundPaint = Paint(progressRingPaint).apply {
                alpha = 50
                color = Color.GRAY
            }
            canvas.drawCircle(centerX, centerY, radius, backgroundPaint)
            
            // Draw progress arc
            if (progress > 0f) {
                val sweepAngle = progress * 360f
                val rect = RectF(
                    centerX - radius,
                    centerY - radius,
                    centerX + radius,
                    centerY + radius
                )
                
                canvas.drawArc(rect, -90f, sweepAngle, false, progressRingPaint)
            }
        } catch (e: Exception) {
            // Ignore drawing errors
        }
    }
    
    private fun drawMiniVisualizer(canvas: Canvas) {
        try {
            // Progress bar not available in this layout - use mini player dimensions
            val barWidth = width.toFloat()
            val barHeight = 4f // Small visualizer height
            val barX = 0f
            val barY = height.toFloat() - barHeight
            
            val barSpacing = barWidth / audioData.size
            
            for (i in audioData.indices) {
                val barLeft = barX + i * barSpacing
                val barRight = barLeft + barSpacing * 0.8f
                val barTop = barY + barHeight * (1f - audioData[i])
                val barBottom = barY + barHeight
                
                canvas.drawRect(
                    barLeft,
                    barTop,
                    barRight,
                    barBottom,
                    miniVisualizerPaint
                )
            }
        } catch (e: Exception) {
            // Ignore drawing errors
        }
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
            AnimationUtils.animateButtonPress(view)
            
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

        // Previous button click listener
        binding.miniPreviousButton.setOnClickListener { view ->
            AnimationUtils.animateButtonPress(view)
            handlePreviousTrack()
        }
        
        binding.miniNextButton.setOnClickListener { view ->
            AnimationUtils.animateButtonPress(view)
            
            try {
                mediaController?.seekToNext() ?: musicPlayerManager?.skipToNext()
            } catch (e: Exception) {
                android.util.Log.w("MiniPlayerView", "Next action failed", e)
            }
        }

        // Fast forward button click listener
        binding.miniFastForwardButton.setOnClickListener { view ->
            AnimationUtils.animateButtonPress(view)
            // Fast forward 30 seconds
            mediaController?.let { controller ->
                val currentPos = controller.currentPosition
                val newPos = (currentPos + 30000).coerceAtMost(controller.duration)
                controller.seekTo(newPos)
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
                    miniVisualizerAnimator?.start()
                    show()
                } else {
                    // Keep visible when paused, only hide if idle with no item
                    stopProgressUpdates()
                    miniVisualizerAnimator?.pause()
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

    override fun resync() { resyncFromController() }

    private fun resyncFromController() {
        try {
            val controller = mediaController ?: return
            if (controller.currentMediaItem != null || controller.playbackState == Player.STATE_READY || controller.isPlaying) {
                updateMediaInfo()
                setArtworkFromMetadata()
                updatePlayPauseButton(controller.isPlaying)
                updateProgressBar(controller.currentPosition, controller.duration)
                if (controller.isPlaying) {
                    startProgressUpdates()
                    miniVisualizerAnimator?.start()
                } else {
                    stopProgressUpdates()
                    miniVisualizerAnimator?.pause()
                }
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
            // Initialize position for slide-up animation
            translationY = height.toFloat()
            visibility = VISIBLE
            
            // Slide up animation with fade in
            animate()
                .translationY(0f)
                .alpha(1f)
                .setDuration(350)
                .setInterpolator(android.view.animation.DecelerateInterpolator())
                .start()
                
            // Animate child views with stagger effect
            animateChildViews(true)
        }
    }

    fun hide() {
        if (visibility == VISIBLE) {
            // Slide down animation with fade out
            animate()
                .translationY(height.toFloat())
                .alpha(0f)
                .setDuration(300)
                .setInterpolator(android.view.animation.AccelerateInterpolator())
                .withEndAction {
                    visibility = GONE
                    alpha = 1f // Reset alpha for next show
                }
                .start()
                
            // Animate child views with stagger effect  
            animateChildViews(false)
        }
    }

    private fun setupAlbumArtworkSeekGesture() {
        binding.miniAlbumArt.setOnTouchListener { view, event ->
            if (event.action == android.view.MotionEvent.ACTION_UP) {
                val viewWidth = view.width
                val touchX = event.x
                val leftHalf = viewWidth / 2f
                
                // Add ripple effect
                AnimationUtils.animateButtonPress(view)
                
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
                            showVisualFeedbackViaParent("⏪ -10s")
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
                            showVisualFeedbackViaParent("⏩ +10s")
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
    override fun applyAppearancePreferences(prefs: AppearancePreferences) {
        try {
            val density = resources.displayMetrics.density
            val uiScale = (ThemeManager.getAdaptiveUiScale(context) * if (prefs.miniPlayerCompactMode) 0.92f else 1.0f)
                .coerceIn(0.74f, 0.96f)
            val buttonScale = (uiScale * prefs.buttonSizeScale).coerceIn(0.72f, 1.0f)
            val rootHeight = ((prefs.miniPlayerHeightDp.coerceIn(62, 76)) * density * uiScale).roundToInt()

            fun px(baseDp: Int, scale: Float = uiScale): Int =
                (baseDp * density * scale).roundToInt().coerceAtLeast(1)

            fun updateSize(view: View, widthDp: Int, heightDp: Int, scale: Float = uiScale) {
                view.layoutParams = view.layoutParams.apply {
                    width = px(widthDp, scale)
                    height = px(heightDp, scale)
                }
            }

            fun updateMargins(
                view: View,
                startDp: Int? = null,
                topDp: Int? = null,
                endDp: Int? = null,
                bottomDp: Int? = null,
                scale: Float = uiScale
            ) {
                val lp = view.layoutParams as? MarginLayoutParams ?: return
                startDp?.let { lp.marginStart = px(it, scale) }
                topDp?.let { lp.topMargin = px(it, scale) }
                endDp?.let { lp.marginEnd = px(it, scale) }
                bottomDp?.let { lp.bottomMargin = px(it, scale) }
                view.layoutParams = lp
            }

            layoutParams = layoutParams?.apply {
                height = rootHeight
            }
            minimumHeight = rootHeight
            setPadding(px(if (prefs.miniPlayerCompactMode) 3 else 6, 1f), px(if (prefs.miniPlayerCompactMode) 3 else 6, 1f), px(if (prefs.miniPlayerCompactMode) 3 else 6, 1f), px(if (prefs.miniPlayerCompactMode) 3 else 6, 1f))

            updateSize(binding.miniAlbumArtCard, 52, 52)
            updateMargins(binding.miniAlbumArtCard, startDp = 12)
            updateSize(binding.miniAlbumArt, 40, 40)
            updateMargins(binding.miniSongInfo, startDp = 10, endDp = 10)
            updateSize(binding.miniPreviousButton, 44, 44, buttonScale)
            updateSize(binding.miniPlayPauseButton, 52, 52, buttonScale)
            updateSize(binding.miniNextButton, 44, 44, buttonScale)
            updateSize(binding.miniFastForwardButton, 44, 44, buttonScale)
            updateMargins(binding.miniPreviousButton, scale = buttonScale, topDp = 3, endDp = 0, bottomDp = 3, startDp = 3)
            updateMargins(binding.miniPlayPauseButton, scale = buttonScale, topDp = 3, endDp = 0, bottomDp = 3, startDp = 3)
            updateMargins(binding.miniNextButton, scale = buttonScale, topDp = 3, endDp = 0, bottomDp = 3, startDp = 3)
            updateMargins(binding.miniFastForwardButton, scale = buttonScale, topDp = 3, endDp = 0, bottomDp = 3, startDp = 3)

            binding.miniAlbumArtCard.visibility = if (prefs.miniPlayerShowArt) VISIBLE else GONE
            
            // Show/hide artist name
            binding.miniArtistName.visibility = if (prefs.miniPlayerShowArtist) VISIBLE else GONE
            
            // Apply compact mode
            if (prefs.miniPlayerCompactMode) {
                val compactPadding = px(4, 1f)
                setPadding(compactPadding, compactPadding, compactPadding, compactPadding)
                binding.miniSongTitle.maxLines = 1
                binding.miniArtistName.maxLines = 1
            } else {
                val normalPadding = px(6, 1f)
                setPadding(normalPadding, normalPadding, normalPadding, normalPadding)
                binding.miniSongTitle.maxLines = 2
                binding.miniArtistName.maxLines = 1
            }

            binding.miniSongTitle.textSize = ThemeManager.scaleSp(
                context,
                if (prefs.miniPlayerCompactMode) 12f else 13f,
                prefs.fontScale
            )
            binding.miniArtistName.textSize = ThemeManager.scaleSp(
                context,
                if (prefs.miniPlayerCompactMode) 10f else 11f,
                prefs.fontScale
            )
            
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

    private fun showVisualFeedbackViaParent(message: String) {
        try {
            // Try to use the parent activity's visual feedback system
            val activity = context as? MainActivity
            activity?.showPlayingBanner(message)
        } catch (e: Exception) {
            // Fallback to a simple visual indicator within the mini player itself
            binding.miniSongTitle.text = message
            postDelayed({ 
                updateMediaInfo() // Restore original title
            }, 1500)
        }
    }
    
    override fun release() {
        stopProgressUpdates()
        stopSpinningAnimation()
        stopMiniVisualizer()
        carouselAnimator?.cancel()
        velocityTracker?.recycle()
        velocityTracker = null
        mediaController?.release()
    }

    override fun asView(): View = this
    
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
    
    private fun animateChildViews(isShowing: Boolean) {
        val childViews = listOf(
            binding.miniAlbumArt,
            binding.miniSongTitle,
            binding.miniArtistName,
            binding.miniPlayPauseButton,
            binding.miniNextButton,
            binding.miniPreviousButton,
            binding.miniFastForwardButton
        )
        
        if (isShowing) {
            // Staggered entrance animation
            childViews.forEachIndexed { index, view ->
                view.alpha = 0f
                view.scaleX = 0.8f
                view.scaleY = 0.8f
                view.animate()
                    .alpha(1f)
                    .scaleX(1f)
                    .scaleY(1f)
                    .setStartDelay((index * 50).toLong())
                    .setDuration(300)
                    .setInterpolator(android.view.animation.OvershootInterpolator(1.2f))
                    .start()
            }
        } else {
            // Staggered exit animation
            childViews.reversed().forEachIndexed { index, view ->
                view.animate()
                    .alpha(0f)
                    .scaleX(0.8f)
                    .scaleY(0.8f)
                    .setStartDelay((index * 30).toLong())
                    .setDuration(200)
                    .setInterpolator(android.view.animation.AccelerateInterpolator())
                    .start()
            }
        }
    }
}
