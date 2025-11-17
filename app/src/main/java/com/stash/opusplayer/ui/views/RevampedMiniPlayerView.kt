package com.stash.opusplayer.ui.views

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.*
import android.graphics.drawable.Drawable
import android.util.AttributeSet
import android.util.Log
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.widget.*
import androidx.cardview.widget.CardView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.content.ContextCompat
import androidx.lifecycle.findViewTreeLifecycleOwner
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import com.bumptech.glide.Glide
import com.bumptech.glide.load.DataSource
import com.bumptech.glide.load.engine.GlideException
import com.bumptech.glide.load.resource.bitmap.RoundedCorners
import com.bumptech.glide.request.RequestListener
import com.bumptech.glide.request.target.Target
import com.stash.opusplayer.R
import com.stash.opusplayer.databinding.ViewRevampedMiniPlayerBinding
import com.stash.opusplayer.player.MusicPlayerManager
import com.stash.opusplayer.ui.appearance.VisualCustomizationManager
import com.stash.opusplayer.utils.AnimationUtils
import com.stash.opusplayer.data.Song
import kotlinx.coroutines.launch
import kotlinx.coroutines.Job
import kotlin.math.*

/**
 * Revamped Mini Player with modern design, enhanced gestures, and advanced features
 */
class RevampedMiniPlayerView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : ConstraintLayout(context, attrs, defStyleAttr) {

    companion object {
        private const val TAG = "RevampedMiniPlayerView"
        private const val SWIPE_THRESHOLD = 100f
        private const val VELOCITY_THRESHOLD = 1000f
        private const val DOUBLE_TAP_TIMEOUT = 300L
        private const val LONG_PRESS_TIMEOUT = 500L
        private const val PROGRESS_UPDATE_INTERVAL = 100L
    }

    private val binding: ViewRevampedMiniPlayerBinding
    private val customizationManager = VisualCustomizationManager(context)

    // Player management
    private var musicPlayerManager: MusicPlayerManager? = null
    private var currentSong: Song? = null
    private var isPlaying = false
    private var currentPosition = 0L
    private var duration = 0L
    private val observationJobs = mutableListOf<Job>()

    // Gesture handling
    private var startX = 0f
    private var startY = 0f
    private var lastTapTime = 0L
    private var longPressRunnable: Runnable? = null

    // Animation
    private var progressAnimator: ValueAnimator? = null
    private var pulseAnimator: ValueAnimator? = null
    private var albumArtRotationAnimator: ValueAnimator? = null

    // Visual effects
    private var spectrumData: FloatArray? = null
    private var spectrumPaint = Paint().apply {
        color = ContextCompat.getColor(context, R.color.accent_color)
        style = Paint.Style.FILL
    }

    // Callbacks
    private var onExpandListener: (() -> Unit)? = null
    private var onNextListener: (() -> Unit)? = null
    private var onPreviousListener: (() -> Unit)? = null
    private var onPlayPauseListener: (() -> Unit)? = null
    private var onSeekListener: ((position: Long) -> Unit)? = null

    init {
        binding = ViewRevampedMiniPlayerBinding.inflate(LayoutInflater.from(context), this, true)
        setupUI()
        setupGestureHandling()
        setupAnimations()
        applyAppearancePreferences()
    }

    private fun setupUI() {
        // Apply modern card styling
        binding.miniPlayerCard.apply {
            cardElevation = 12f
            radius = 24f
            useCompatPadding = true
        }

        // Setup click listeners
        binding.playPauseButton.setOnClickListener {
            AnimationUtils.animateButtonPress(it) {
                onPlayPauseListener?.invoke()
            }
        }

        binding.nextButton.setOnClickListener {
            AnimationUtils.animateButtonPress(it) {
                onNextListener?.invoke()
            }
        }

        binding.previousButton.setOnClickListener {
            AnimationUtils.animateButtonPress(it) {
                onPreviousListener?.invoke()
            }
        }

        // Setup progress bar
        binding.progressBar.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                if (fromUser) {
                    val position = (progress / 100f * duration).toLong()
                    binding.currentTimeText.text = formatTime(position)
                }
            }

            override fun onStartTrackingTouch(seekBar: SeekBar?) {
                progressAnimator?.cancel()
            }

            override fun onStopTrackingTouch(seekBar: SeekBar?) {
                val progress = seekBar?.progress ?: 0
                val position = (progress / 100f * duration).toLong()
                onSeekListener?.invoke(position)
                startProgressAnimation()
            }
        })

        // Setup visualizer canvas - custom drawing will be handled by the view itself
        binding.visualizerView.setWillNotDraw(false)
    }

    private fun setupGestureHandling() {
        binding.miniPlayerCard.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    startX = event.x
                    startY = event.y
                    
                    // Setup long press detection
                    longPressRunnable = Runnable {
                        handleLongPress()
                    }
                    postDelayed(longPressRunnable, LONG_PRESS_TIMEOUT)
                    
                    true
                }

                MotionEvent.ACTION_MOVE -> {
                    val deltaX = abs(event.x - startX)
                    val deltaY = abs(event.y - startY)
                    
                    if (deltaX > 20f || deltaY > 20f) {
                        longPressRunnable?.let { removeCallbacks(it) }
                    }
                    
                    true
                }

                MotionEvent.ACTION_UP -> {
                    longPressRunnable?.let { removeCallbacks(it) }
                    
                    val deltaX = event.x - startX
                    val deltaY = event.y - startY
                    val distance = sqrt(deltaX.pow(2) + deltaY.pow(2))
                    
                    when {
                        distance < 20f -> handleTap() // Single tap or double tap
                        abs(deltaX) > abs(deltaY) -> handleHorizontalSwipe(deltaX)
                        abs(deltaY) > abs(deltaX) -> handleVerticalSwipe(deltaY)
                    }
                    
                    true
                }

                else -> false
            }
        }
    }

    private fun handleTap() {
        val currentTime = System.currentTimeMillis()
        if (currentTime - lastTapTime < DOUBLE_TAP_TIMEOUT) {
            // Double tap - toggle play/pause
            onPlayPauseListener?.invoke()
        } else {
            // Single tap - expand player
            postDelayed({
                if (System.currentTimeMillis() - lastTapTime >= DOUBLE_TAP_TIMEOUT) {
                    onExpandListener?.invoke()
                }
            }, DOUBLE_TAP_TIMEOUT)
        }
        lastTapTime = currentTime
    }

    private fun handleHorizontalSwipe(deltaX: Float) {
        if (abs(deltaX) > SWIPE_THRESHOLD) {
            if (deltaX > 0) {
                // Swipe right - next track
                AnimationUtils.animateSlideOut(binding.albumArtContainer, true) {
                    onNextListener?.invoke()
                    AnimationUtils.animateSlideIn(binding.albumArtContainer, true)
                }
            } else {
                // Swipe left - previous track
                AnimationUtils.animateSlideOut(binding.albumArtContainer, false) {
                    onPreviousListener?.invoke()
                    AnimationUtils.animateSlideIn(binding.albumArtContainer, false)
                }
            }
        }
    }

    private fun handleVerticalSwipe(deltaY: Float) {
        if (abs(deltaY) > SWIPE_THRESHOLD) {
            if (deltaY < 0) {
                // Swipe up - expand player
                onExpandListener?.invoke()
            } else {
                // Swipe down - minimize or hide
                AnimationUtils.animateFadeOut(this)
            }
        }
    }

    private fun handleLongPress() {
        // Long press - show context menu or queue
        AnimationUtils.animateButtonPress(this) {
            // Show queue or options menu
            showOptionsMenu()
        }
    }

    private fun setupAnimations() {
        // Pulse animation for play button when playing
        pulseAnimator = ValueAnimator.ofFloat(1f, 1.1f, 1f).apply {
            duration = 1000
            repeatMode = ValueAnimator.RESTART
            repeatCount = ValueAnimator.INFINITE
            addUpdateListener { animation ->
                val scale = animation.animatedValue as Float
                binding.playPauseButton.scaleX = scale
                binding.playPauseButton.scaleY = scale
            }
        }

        // Album art rotation when playing
        albumArtRotationAnimator = ValueAnimator.ofFloat(0f, 360f).apply {
            duration = 30000
            repeatMode = ValueAnimator.RESTART
            repeatCount = ValueAnimator.INFINITE
            addUpdateListener { animation ->
                val rotation = animation.animatedValue as Float
                binding.albumArt.rotation = rotation
            }
        }
    }

    private fun startProgressAnimation() {
        progressAnimator?.cancel()
        
        progressAnimator = ValueAnimator.ofInt(
            ((currentPosition * 100) / duration).toInt(),
            100
        ).apply {
            duration = duration - currentPosition
            addUpdateListener { animation ->
                val progress = animation.animatedValue as Int
                binding.progressBar.progress = progress
                
                val pos = (progress / 100f * duration).toLong()
                binding.currentTimeText.text = formatTime(pos)
            }
        }
        
        if (isPlaying) {
            progressAnimator?.start()
        }
    }

    private fun drawMiniVisualizer(canvas: Canvas) {
        val spectrum = spectrumData ?: return
        if (spectrum.isEmpty()) return

        val width = canvas.width.toFloat()
        val height = canvas.height.toFloat()
        val barWidth = width / spectrum.size
        
        for (i in spectrum.indices) {
            val amplitude = spectrum[i]
            val barHeight = (amplitude / 255f) * height * 0.8f
            
            val left = i * barWidth
            val right = left + barWidth * 0.8f
            val bottom = height
            val top = bottom - barHeight

            canvas.drawRect(left, top, right, bottom, spectrumPaint)
        }
    }

    private fun showOptionsMenu() {
        // Create and show popup menu with queue, favorites, etc.
        val popup = PopupMenu(context, this)
        popup.menuInflater.inflate(R.menu.mini_player_options, popup.menu)
        
        popup.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                R.id.action_show_queue -> {
                    // Show queue
                    true
                }
                R.id.action_add_to_favorites -> {
                    // Add to favorites
                    true
                }
                R.id.action_share -> {
                    // Share track
                    true
                }
                else -> false
            }
        }
        
        popup.show()
    }

    private fun formatTime(milliseconds: Long): String {
        val seconds = (milliseconds / 1000) % 60
        val minutes = (milliseconds / (1000 * 60)) % 60
        val hours = (milliseconds / (1000 * 60 * 60))
        
        return if (hours > 0) {
            String.format("%d:%02d:%02d", hours, minutes, seconds)
        } else {
            String.format("%d:%02d", minutes, seconds)
        }
    }

    // Public API methods
    fun setMusicPlayerManager(manager: MusicPlayerManager) {
        this.musicPlayerManager = manager
        
        // Cancel any existing observation jobs
        observationJobs.forEach { it.cancel() }
        observationJobs.clear()
        
        val lifecycleOwner = findViewTreeLifecycleOwner() ?: return
        
        // Observe player state
        lifecycleOwner.lifecycleScope.launch {
            lifecycleOwner.lifecycle.repeatOnLifecycle(androidx.lifecycle.Lifecycle.State.STARTED) {
                manager.isPlaying.collect { playing ->
                    updatePlayingState(playing)
                }
            }
        }.also { observationJobs.add(it) }
        
        lifecycleOwner.lifecycleScope.launch {
            lifecycleOwner.lifecycle.repeatOnLifecycle(androidx.lifecycle.Lifecycle.State.STARTED) {
                manager.currentSong.collect { song ->
                    updateCurrentSong(song)
                }
            }
        }.also { observationJobs.add(it) }
        
        lifecycleOwner.lifecycleScope.launch {
            lifecycleOwner.lifecycle.repeatOnLifecycle(androidx.lifecycle.Lifecycle.State.STARTED) {
                manager.currentPosition.collect { position ->
                    updatePosition(position)
                }
            }
        }.also { observationJobs.add(it) }
        
        // Update duration periodically since it's not a flow
        // Use repeatOnLifecycle to automatically cancel when view is not visible
        lifecycleOwner.lifecycleScope.launch {
            lifecycleOwner.lifecycle.repeatOnLifecycle(androidx.lifecycle.Lifecycle.State.STARTED) {
                while (true) {
                    val dur = manager.getDuration()
                    if (dur > 0 && dur != duration) {
                        updateDuration(dur)
                    }
                    kotlinx.coroutines.delay(1000) // Check every second
                }
            }
        }.also { observationJobs.add(it) }
    }

    fun setSpectrumData(spectrum: FloatArray) {
        this.spectrumData = spectrum
        binding.visualizerView.invalidate()
    }

    fun setOnExpandListener(listener: () -> Unit) {
        this.onExpandListener = listener
    }

    fun setOnNextListener(listener: () -> Unit) {
        this.onNextListener = listener
    }

    fun setOnPreviousListener(listener: () -> Unit) {
        this.onPreviousListener = listener
    }

    fun setOnPlayPauseListener(listener: () -> Unit) {
        this.onPlayPauseListener = listener
    }

    fun setOnSeekListener(listener: (Long) -> Unit) {
        this.onSeekListener = listener
    }

    private fun updatePlayingState(playing: Boolean) {
        isPlaying = playing
        
        // Update play/pause button
        val iconRes = if (playing) R.drawable.ic_pause_24 else R.drawable.ic_play_arrow
        binding.playPauseButton.setImageResource(iconRes)
        
        // Start/stop animations
        if (playing) {
            pulseAnimator?.start()
            albumArtRotationAnimator?.start()
            startProgressAnimation()
        } else {
            pulseAnimator?.cancel()
            albumArtRotationAnimator?.cancel()
            progressAnimator?.pause()
        }
    }

    private fun updateCurrentSong(song: Song?) {
        currentSong = song
        
        if (song != null) {
            // Update track info
            binding.trackTitle.text = song.displayName
            binding.trackArtist.text = song.artistName
            
            // Apply visibility preferences
            applyAppearancePreferences()
            
            // Load album art with rounded corners and placeholder
            // Handle null or empty album art gracefully
            val artworkData = if (song.albumArt.isNullOrBlank()) {
                android.R.drawable.ic_media_play
            } else {
                song.albumArt
            }
            
            Glide.with(context)
                .load(artworkData)
                .transform(RoundedCorners(24))
                .placeholder(android.R.drawable.ic_media_play)
                .error(android.R.drawable.ic_media_play)
                .listener(object : RequestListener<Drawable> {
                    override fun onLoadFailed(
                        e: GlideException?, 
                        model: Any?, 
                        target: Target<Drawable>, 
                        isFirstResource: Boolean
                    ): Boolean {
                        Log.d(TAG, "Using placeholder for album art")
                        return false
                    }
                    
                    override fun onResourceReady(
                        resource: Drawable, 
                        model: Any, 
                        target: Target<Drawable>, 
                        dataSource: DataSource, 
                        isFirstResource: Boolean
                    ): Boolean {
                        // Animate album art appearance
                        AnimationUtils.animateFadeIn(binding.albumArt)
                        return false
                    }
                })
                .into(binding.albumArt)
                
            // Show the mini player
            AnimationUtils.animateFadeIn(this)
        } else {
            // Hide when no media
            AnimationUtils.animateFadeOut(this)
        }
    }

    private fun updatePosition(position: Long) {
        currentPosition = position
        
        if (duration > 0) {
            val progress = ((position * 100) / duration).toInt()
            binding.progressBar.progress = progress
            binding.currentTimeText.text = formatTime(position)
        }
    }

    private fun updateDuration(dur: Long) {
        duration = dur
        binding.totalTimeText.text = formatTime(dur)
        binding.progressBar.max = 100
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        // Cancel all coroutines observing player state
        observationJobs.forEach { it.cancel() }
        observationJobs.clear()
        // Cancel animations
        progressAnimator?.cancel()
        pulseAnimator?.cancel()
        albumArtRotationAnimator?.cancel()
        longPressRunnable?.let { removeCallbacks(it) }
    }

    // Custom drawing setup - removed problematic onDraw access
    private fun setupCustomDrawing() {
        binding.visualizerView.setWillNotDraw(false)
        // Custom drawing is handled in the visualizer view's onDraw override
    }
    
    /**
     * Apply appearance preferences from settings
     */
    fun applyAppearancePreferences() {
        try {
            val prefs = com.stash.opusplayer.ui.appearance.AppearancePreferences.fromPrefs(context)
            
            // Show/hide album art
            binding.albumArtContainer.visibility = if (prefs.miniPlayerShowArt) View.VISIBLE else View.GONE
            
            // Show/hide artist
            binding.trackArtist.visibility = if (prefs.miniPlayerShowArtist) View.VISIBLE else View.GONE
            
            // Apply compact mode
            if (prefs.miniPlayerCompactMode) {
                // Reduce padding and text sizes for compact mode
                binding.trackTitle.textSize = 12f
                binding.trackArtist.textSize = 10f
                binding.miniPlayerCard.apply {
                    setPadding(8, 4, 8, 4)
                    cardElevation = 8f
                }
            } else {
                // Normal mode
                binding.trackTitle.textSize = 14f
                binding.trackArtist.textSize = 12f
                binding.miniPlayerCard.apply {
                    setPadding(12, 8, 12, 8)
                    cardElevation = 12f
                }
            }
            
            // Apply bottom margin offset
            val bottomOffset = context.getSharedPreferences("settings", 0)
                .getInt("miniplayer_bottom_offset", 72)
            
            // Null-safe layout parameter handling with fallback
            (layoutParams as? android.view.ViewGroup.MarginLayoutParams)?.let { params ->
                params.bottomMargin = (bottomOffset * resources.displayMetrics.density).toInt()
                layoutParams = params
            } ?: run {
                // Fallback: create new MarginLayoutParams if cast fails
                val newParams = android.view.ViewGroup.MarginLayoutParams(
                    android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                    android.view.ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply {
                    bottomMargin = (bottomOffset * resources.displayMetrics.density).toInt()
                }
                layoutParams = newParams
            }
            
            requestLayout()
        } catch (e: Exception) {
            Log.e(TAG, "Error applying appearance preferences", e)
        }
    }
}
