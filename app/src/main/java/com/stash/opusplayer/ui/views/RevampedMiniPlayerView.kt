package com.stash.opusplayer.ui.views

import android.content.Intent
import android.content.res.ColorStateList
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.*
import android.graphics.drawable.Drawable
import android.util.AttributeSet
import android.util.Log
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.*
import androidx.cardview.widget.CardView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.content.ContextCompat
import androidx.core.graphics.ColorUtils
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.lifecycleScope
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
import com.stash.opusplayer.ui.MiniPlayerSurface
import com.stash.opusplayer.ui.NowPlayingActivity
import com.stash.opusplayer.ui.QueueActivity
import com.stash.opusplayer.ui.appearance.VisualCustomizationManager
import com.stash.opusplayer.ui.appearance.AppearancePreferences
import com.stash.opusplayer.ui.appearance.ThemeManager
import com.stash.opusplayer.utils.AnimationUtils
import com.stash.opusplayer.utils.MetadataExtractor
import com.stash.opusplayer.data.Song
import kotlinx.coroutines.launch
import kotlin.math.*

/**
 * Revamped Mini Player with modern design, enhanced gestures, and advanced features
 */
class RevampedMiniPlayerView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : ConstraintLayout(context, attrs, defStyleAttr), MiniPlayerSurface {

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
    private val metadataExtractor = MetadataExtractor(context)

    // Player management
    private var musicPlayerManager: MusicPlayerManager? = null
    private var lifecycleOwner: LifecycleOwner? = null
    private var hasBoundToManager = false
    private var currentSong: Song? = null
    private var isPlaying = false
    private var currentPosition = 0L
    private var duration = 0L

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
        if (duration <= 0L) return
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
                    runCatching {
                        context.startActivity(Intent(context, QueueActivity::class.java).apply {
                            if (context !is android.app.Activity) addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        })
                    }
                    true
                }
                R.id.action_add_to_favorites -> {
                    val song = currentSong ?: return@setOnMenuItemClickListener false
                    (context as? com.stash.opusplayer.ui.MainActivity)?.toggleFavorite(song)
                    true
                }
                R.id.action_share -> {
                    shareCurrentTrack()
                    true
                }
                else -> false
            }
        }
        
        popup.show()
    }

    private fun shareCurrentTrack() {
        val song = currentSong ?: return
        val text = "${song.displayName} - ${song.artistName}"
        runCatching {
            context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, text)
                if (context !is android.app.Activity) addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }, context.getString(R.string.share)))
        }
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

    override fun initialize(lifecycleOwner: LifecycleOwner, musicPlayerManager: MusicPlayerManager) {
        this.lifecycleOwner = lifecycleOwner
        if (this.musicPlayerManager !== musicPlayerManager || !hasBoundToManager) {
            this.musicPlayerManager = musicPlayerManager
            observePlayerManager(lifecycleOwner, musicPlayerManager)
            hasBoundToManager = true
        }

        setOnExpandListener { openNowPlaying() }
        setOnPlayPauseListener {
            val manager = this.musicPlayerManager ?: return@setOnPlayPauseListener
            if (manager.isPlaying.value) manager.pause() else manager.play()
        }
        setOnNextListener { this.musicPlayerManager?.skipToNext() }
        setOnPreviousListener { this.musicPlayerManager?.skipToPrevious() }
        setOnSeekListener { position -> this.musicPlayerManager?.seekTo(position) }

        resync()
    }

    private fun openNowPlaying() {
        runCatching {
            context.startActivity(Intent(context, NowPlayingActivity::class.java).apply {
                currentSong?.let { putExtra("song", it) }
                if (context !is android.app.Activity) addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            })
        }
    }

    private fun observePlayerManager(owner: LifecycleOwner, manager: MusicPlayerManager) {
        this.musicPlayerManager = manager
        
        // Observe player state
        owner.lifecycleScope.launch {
            manager.isPlaying.collect { playing ->
                updatePlayingState(playing)
            }
        }
        
        owner.lifecycleScope.launch {
            manager.currentSong.collect { song ->
                updateCurrentSong(song)
            }
        }
        
        owner.lifecycleScope.launch {
            manager.currentPosition.collect { position ->
                updatePosition(position)
            }
        }
        
        // Update duration periodically since it's not a flow
        owner.lifecycleScope.launch {
            while (true) {
                val dur = manager.getDuration()
                if (dur > 0 && dur != duration) {
                    updateDuration(dur)
                }
                kotlinx.coroutines.delay(1000) // Check every second
            }
        }
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
        val iconRes = if (playing) R.drawable.ic_pause_24 else R.drawable.ic_play_arrow_24
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
            
            val cached = metadataExtractor.loadCachedArtwork(context, song)
            val embedded = metadataExtractor.decodeAlbumArt(song.albumArt)
            val artModel: Any = cached ?: embedded ?: song.albumArt ?: R.drawable.ic_music_note

            Glide.with(context)
                .load(artModel)
                .transform(RoundedCorners(24))
                .placeholder(R.drawable.ic_music_note)
                .error(R.drawable.ic_music_note)
                .listener(object : RequestListener<Drawable> {
                    override fun onLoadFailed(
                        e: GlideException?, 
                        model: Any?, 
                        target: Target<Drawable>, 
                        isFirstResource: Boolean
                    ): Boolean {
                        Log.w(TAG, "Failed to load album art", e)
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

    override fun resync() {
        val manager = musicPlayerManager ?: return
        updateCurrentSong(manager.currentSong.value)
        updatePlayingState(manager.isPlaying.value)
        updateDuration(manager.getDuration())
        updatePosition(manager.currentPosition.value)
    }

    override fun applyAppearancePreferences(prefs: AppearancePreferences) {
        val density = resources.displayMetrics.density
        val uiScale = (ThemeManager.getAdaptiveUiScale(context) * if (prefs.miniPlayerCompactMode) 0.9f else 0.96f)
            .coerceIn(0.68f, 0.9f)
        val buttonScale = (uiScale * prefs.buttonSizeScale).coerceIn(0.66f, 0.92f)
        val compactAlpha = if (prefs.miniPlayerCompactMode) 0.96f else 1f

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

        binding.miniPlayerCard.radius = prefs.cardCornerRadiusDp * density * uiScale
        binding.miniPlayerCard.setCardBackgroundColor(prefs.primaryColor)
        binding.miniPlayerCard.cardElevation = px(if (prefs.miniPlayerCompactMode) 4 else 8, 1f).toFloat()
        binding.miniPlayerCard.useCompatPadding = !prefs.miniPlayerCompactMode
        updateMargins(binding.miniPlayerCard, startDp = 4, topDp = 4, endDp = 4, bottomDp = 4)

        binding.root.layoutParams = binding.root.layoutParams.apply {
            height = ViewGroup.LayoutParams.WRAP_CONTENT
        }
        binding.root.minimumHeight = px(if (prefs.miniPlayerCompactMode) 60 else 68, 1f)
        binding.root.setPadding(px(if (prefs.miniPlayerCompactMode) 8 else 10, 1f), px(if (prefs.miniPlayerCompactMode) 8 else 10, 1f), px(if (prefs.miniPlayerCompactMode) 8 else 10, 1f), px(if (prefs.miniPlayerCompactMode) 8 else 10, 1f))

        updateSize(binding.albumArtContainer, 46, 46)
        updateMargins(binding.trackInfoContainer, startDp = 8, endDp = 8)
        updateMargins(binding.progressContainer, startDp = 8, topDp = 4, endDp = 8)
        updateSize(binding.previousButton, 28, 28, buttonScale)
        updateSize(binding.playPauseButton, 36, 36, buttonScale)
        updateSize(binding.nextButton, 28, 28, buttonScale)
        updateMargins(binding.previousButton, endDp = 2, scale = buttonScale)
        updateMargins(binding.playPauseButton, endDp = 2, scale = buttonScale)

        binding.trackTitle.textSize = ThemeManager.scaleSp(context, if (prefs.miniPlayerCompactMode) 12f else 13f, prefs.fontScale)
        binding.trackArtist.textSize = ThemeManager.scaleSp(context, if (prefs.miniPlayerCompactMode) 9.5f else 10f, prefs.fontScale)
        binding.currentTimeText.textSize = ThemeManager.scaleSp(context, 9f, prefs.fontScale)
        binding.totalTimeText.textSize = ThemeManager.scaleSp(context, 9f, prefs.fontScale)

        binding.trackTitle.setTextColor(prefs.textPrimaryColor)
        binding.trackArtist.setTextColor(prefs.textSecondaryColor)
        binding.trackArtist.visibility = if (prefs.miniPlayerShowArtist) View.VISIBLE else View.GONE
        binding.albumArtContainer.visibility = if (prefs.miniPlayerShowArt) View.VISIBLE else View.GONE
        val surface = ColorUtils.blendARGB(prefs.primaryColor, prefs.backgroundColor, 0.42f)
        val accentSurface = ColorUtils.blendARGB(prefs.accentColor, prefs.primaryColor, 0.3f)
        val subtleButton = ColorUtils.blendARGB(surface, prefs.backgroundColor, 0.16f)
        binding.trackArtist.background?.mutate()?.setTint(ColorUtils.blendARGB(accentSurface, prefs.backgroundColor, 0.5f))
        binding.previousButton.imageTintList = ColorStateList.valueOf(prefs.textSecondaryColor)
        binding.nextButton.imageTintList = ColorStateList.valueOf(prefs.textSecondaryColor)
        binding.playPauseButton.imageTintList = ColorStateList.valueOf(prefs.textPrimaryColor)
        binding.previousButton.backgroundTintList = ColorStateList.valueOf(subtleButton)
        binding.nextButton.backgroundTintList = ColorStateList.valueOf(subtleButton)
        binding.playPauseButton.backgroundTintList = ColorStateList.valueOf(accentSurface)
        binding.progressBar.progressTintList = ColorStateList.valueOf(prefs.accentColor)
        binding.progressBar.thumbTintList = ColorStateList.valueOf(prefs.accentColor)
        binding.progressBar.progressBackgroundTintList = ColorStateList.valueOf(surface)
        binding.currentTimeText.setTextColor(prefs.textSecondaryColor)
        binding.totalTimeText.setTextColor(prefs.textSecondaryColor)
        alpha = compactAlpha
    }

    override fun asView(): View = this

    override fun release() {
        progressAnimator?.cancel()
        pulseAnimator?.cancel()
        albumArtRotationAnimator?.cancel()
        longPressRunnable?.let { removeCallbacks(it) }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        release()
    }

    // Custom drawing setup - removed problematic onDraw access
    private fun setupCustomDrawing() {
        binding.visualizerView.setWillNotDraw(false)
        // Custom drawing is handled in the visualizer view's onDraw override
    }
}
