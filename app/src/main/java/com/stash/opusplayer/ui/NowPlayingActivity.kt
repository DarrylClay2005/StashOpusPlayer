package com.stash.opusplayer.ui

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
import com.stash.opusplayer.R
import com.stash.opusplayer.audio.EqualizerManager
import com.stash.opusplayer.data.Song
import com.stash.opusplayer.databinding.ActivityNowPlayingBinding
import com.stash.opusplayer.player.MusicPlayerManager
import com.stash.opusplayer.service.MusicService
import androidx.core.os.bundleOf
import com.stash.opusplayer.utils.MetadataExtractor
import com.stash.opusplayer.utils.AnimationUtils
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
    
    private val feedbackHandler = Handler(Looper.getMainLooper())
    private var feedbackRunnable: Runnable? = null
    
    private fun showVisualFeedback(message: String) {
        feedbackRunnable?.let { feedbackHandler.removeCallbacks(it) }
        binding.feedbackOverlay.apply {
            text = message
            visibility = android.view.View.VISIBLE
            alpha = 1.0f
        }
        feedbackRunnable = Runnable {
            binding.feedbackOverlay.animate()
                .alpha(0f)
                .setDuration(500)
                .withEndAction {
                    binding.feedbackOverlay.visibility = android.view.View.GONE
                }.start()
        }
        feedbackHandler.postDelayed(feedbackRunnable!!, 1500)
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityNowPlayingBinding.inflate(layoutInflater)
        setContentView(binding.root)
        
        // Animate activity entrance
        animateActivityEntrance()
        
        metadataExtractor = MetadataExtractor(this)
        
        // Apply appearance preferences to EnhancedSynthWave
        try {
            val appearancePrefs = com.stash.opusplayer.ui.appearance.AppearancePreferences.fromPrefs(this)
            binding.enhancedSynthWaveView.applyAppearancePreferences(appearancePrefs)
            
            // Set up seek listener for EnhancedSynthWave progress line
            binding.enhancedSynthWaveView.setOnSeekListener { seekPosition ->
                mediaController?.let { controller ->
                    if (controller.duration > 0) {
                        val targetPosition = (seekPosition * controller.duration).toLong()
                        controller.seekTo(targetPosition)
                        showVisualFeedback("${formatTime(targetPosition)}")
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.w("NowPlayingActivity", "Error applying appearance preferences to EnhancedSynthWave", e)
        }
        
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
    
    private fun animateActivityEntrance() {
        // Fade in the background
        binding.root.alpha = 0f
        binding.root.animate()
            .alpha(1f)
            .setDuration(400)
            .start()
        
        // Slide in controls from bottom
        val controlViews = listOf(
            binding.playPauseButton,
            binding.previousButton,
            binding.nextButton,
            binding.shuffleButton,
            binding.repeatButton
        )
        
        controlViews.forEachIndexed { index, view ->
            view.translationY = 200f
            view.alpha = 0f
            view.animate()
                .translationY(0f)
                .alpha(1f)
                .setStartDelay((index * 100).toLong())
                .setDuration(500)
                .setInterpolator(android.view.animation.DecelerateInterpolator())
                .start()
        }
        
        // Scale in the album art
        try {
            binding.albumArtwork?.let { albumArt ->
                albumArt.scaleX = 0.3f
                albumArt.scaleY = 0.3f
                albumArt.alpha = 0f
                albumArt.animate()
                    .scaleX(1f)
                    .scaleY(1f)
                    .alpha(1f)
                    .setDuration(600)
                    .setStartDelay(200)
                    .setInterpolator(android.view.animation.OvershootInterpolator())
                    .start()
            }
        } catch (e: Exception) {
            // Handle case where albumArtwork view might not exist
        }
    }
    
    private fun setupUI() {
        // Back button with animation
        binding.backButton.setOnClickListener { view ->
            AnimationUtils.animateButtonPress(view) {
                finish()
                AnimationUtils.finishActivityWithSlideOut(this@NowPlayingActivity)
            }
        }
        
        // Playback controls with visual feedback
        binding.playPauseButton.setOnClickListener { view ->
            // Add visual feedback
            view.animate().scaleX(0.9f).scaleY(0.9f).setDuration(100)
                .withEndAction {
                    view.animate().scaleX(1.0f).scaleY(1.0f).setDuration(100).start()
                }.start()
            
            mediaController?.let { controller ->
                if (controller.isPlaying) {
                    controller.pause()
                } else {
                    controller.play()
                }
            }
        }
        
        binding.previousButton.setOnClickListener { view ->
            // Add visual feedback
            view.animate().scaleX(0.9f).scaleY(0.9f).setDuration(100)
                .withEndAction {
                    view.animate().scaleX(1.0f).scaleY(1.0f).setDuration(100).start()
                }.start()
            
            mediaController?.seekToPrevious()
        }
        
        binding.nextButton.setOnClickListener { view ->
            // Add visual feedback
            view.animate().scaleX(0.9f).scaleY(0.9f).setDuration(100)
                .withEndAction {
                    view.animate().scaleX(1.0f).scaleY(1.0f).setDuration(100).start()
                }.start()
            
            mediaController?.seekToNext()
        }
        
        binding.shuffleButton.setOnClickListener {
            mediaController?.let { controller ->
                val enabled = !controller.shuffleModeEnabled
                controller.shuffleModeEnabled = enabled
                updateShuffleButton(enabled)
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
                    R.id.action_share -> { shareCurrentTrack(); true }
                    R.id.action_embed_artwork -> { embedArtworkIntoFile(); true }
                    R.id.action_toggle_crossfade -> {
                        // Quick toggle
                        val prefs = getSharedPreferences("settings", 0)
                        val current = prefs.getBoolean("crossfade_enabled", false)
                        val next = !current
                        prefs.edit().putBoolean("crossfade_enabled", next).apply()
                        // Notify service via command as well
                        try {
                            mediaController?.sendCustomCommand(
                                androidx.media3.session.SessionCommand("SET_CROSSFADE_ENABLED", android.os.Bundle.EMPTY),
                                androidx.core.os.bundleOf("enabled" to next)
                            )
                        } catch (_: Exception) {}
                        // Visual feedback will be shown through menu item state change
                        true
                    }
                    R.id.action_jump_to_source -> {
                        // Ask MainActivity to navigate to the last playback source
                        try {
                            val intent = Intent(this, MainActivity::class.java).apply {
                                action = "com.stash.opusplayer.ACTION_JUMP_TO_SOURCE"
                                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                            }
                            startActivity(intent)
                        } catch (_: Exception) {}
                        true
                    }
                    R.id.action_show_lyrics -> {
                        showLyrics()
                        true
                    }
                    R.id.action_sleep_timer -> {
                        showSleepTimerDialog()
                        true
                    }
                    R.id.action_go_to_album -> {
                        currentSong?.let { s ->
                            try {
                                val intent = Intent(this, MainActivity::class.java).apply {
                                    action = "com.stash.opusplayer.ACTION_GO_TO_ALBUM"
                                    putExtra("album", s.albumName)
                                    addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                                }
                                startActivity(intent)
                            } catch (_: Exception) {}
                        }
                        true
                    }
                    R.id.action_go_to_artist -> {
                        currentSong?.let { s ->
                            try {
                                val intent = Intent(this, MainActivity::class.java).apply {
                                    action = "com.stash.opusplayer.ACTION_GO_TO_ARTIST"
                                    putExtra("artist", s.artistName)
                                    addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                                }
                                startActivity(intent)
                            } catch (_: Exception) {}
                        }
                        true
                    }
                    R.id.action_show_replaygain_info -> {
                        showReplayGainInfo()
                        true
                    }
                    // AB Repeat controls
                    R.id.action_ab_toggle -> {
                        toggleAbRepeat()
                        true
                    }
                    R.id.action_ab_set_a -> {
                        sendAbSetPoint("SET_AB_A")
                        true
                    }
                    R.id.action_ab_set_b -> {
                        sendAbSetPoint("SET_AB_B")
                        true
                    }
                    R.id.action_ab_clear -> {
                        sendAbClear()
                        true
                    }
                    else -> false
                }
            }
            popup.show()
        }

        // Queue button — open full-screen queue
        binding.queueButton.setOnClickListener {
            try {
                startActivity(android.content.Intent(this, QueueActivity::class.java))
            } catch (_: Exception) {}
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
val repository = com.stash.opusplayer.data.MusicRepository(this@NowPlayingActivity)
                        val isFavorite = repository.isFavorite(song.id)
                        
                        if (isFavorite) {
                            repository.removeFromFavorites(song.id)
                            showVisualFeedback("💔 Removed from favorites")
                        } else {
                            repository.addToFavorites(song)
                            showVisualFeedback("❤️ Added to favorites")
                        }
                        
                        // Update UI
                        updateFavoriteButton(!isFavorite)
                        currentSong = song.copy(isFavorite = !isFavorite)
                        
                    } catch (e: Exception) {
                        android.util.Log.e("NowPlayingActivity", "Error toggling favorite", e)
                        showVisualFeedback("Error updating favorites")
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
                    showVisualFeedback("⏩ +30s")
                }
            }
        }
        
        // Add 10-second seek functionality to album artwork
        setupAlbumArtworkSeek()

        // Metadata button now opens full-screen metadata screen
        binding.metadataButton.setOnClickListener {
            try {
                startActivity(android.content.Intent(this, MetadataActivity::class.java))
            } catch (_: Exception) {}
        }
        
        // Metadata back button
        binding.metadataBackButton.setOnClickListener { hideMetadataView() }

        // Audio controls have moved to Settings
    }
    
    private fun showReplayGainBadgeIfEnabled() {
        try {
            val prefs = getSharedPreferences("settings", 0)
            if (!prefs.getBoolean("replaygain_enabled", false)) return
            val controller = mediaController ?: return
            val uri = controller.currentMediaItem?.localConfiguration?.uri ?: return
            lifecycleScope.launch(kotlinx.coroutines.Dispatchers.IO) {
                val info = com.stash.opusplayer.utils.ReplayGainUtil.parseWithCache(this@NowPlayingActivity, uri.toString())
                val mode = prefs.getString("replaygain_mode", "track") ?: "track"
                val preamp = prefs.getFloat("replaygain_preamp_db", 0f)
                val fallback = prefs.getFloat("replaygain_fallback_db", 0f)
                val preventClip = prefs.getBoolean("replaygain_prevent_clipping", true)
                val allowBoost = prefs.getBoolean("replaygain_allow_boost", false)

                val gainDb = when (mode) { "album" -> info?.albumGainDb; else -> info?.trackGainDb }
                val peak = when (mode) { "album" -> info?.albumPeak ?: info?.trackPeak; else -> info?.trackPeak ?: info?.albumPeak } ?: 1f
                var targetDb = (gainDb ?: fallback) + preamp
                if (preventClip && peak > 0f) {
                    val maxDb = 20f * (kotlin.math.log10(1f / peak))
                    if (targetDb > maxDb) targetDb = maxDb
                }
                val text = "ReplayGain: " + String.format("%.2f dB", targetDb)
                launch(kotlinx.coroutines.Dispatchers.Main) {
                    try {
                        binding.replayGainLabel.text = text
                        binding.replayGainLabel.visibility = android.view.View.VISIBLE
                        binding.replayGainLabel.removeCallbacks(null)
                        binding.replayGainLabel.postDelayed({ binding.replayGainLabel.visibility = android.view.View.GONE }, 2500)
                    } catch (_: Exception) {}
                }
            }
        } catch (_: Exception) {}
    }
    
    private fun showReplayGainInfo() {
        try {
            val controller = mediaController ?: return
            val uri = controller.currentMediaItem?.localConfiguration?.uri ?: return
            val info = com.stash.opusplayer.utils.ReplayGainUtil.parseWithCache(this, uri.toString())
            // Read settings to compute effective values similarly to service
            val prefs = getSharedPreferences("settings", 0)
            val enabled = prefs.getBoolean("replaygain_enabled", false)
            val mode = prefs.getString("replaygain_mode", "track") ?: "track"
            val preamp = prefs.getFloat("replaygain_preamp_db", 0f)
            val fallback = prefs.getFloat("replaygain_fallback_db", 0f)
            val preventClip = prefs.getBoolean("replaygain_prevent_clipping", true)
            val allowBoost = prefs.getBoolean("replaygain_allow_boost", false)

            // Compute applied values
            val gainDb = when (mode) {
                "album" -> info?.albumGainDb
                else -> info?.trackGainDb
            }
            val peak = when (mode) {
                "album" -> info?.albumPeak ?: info?.trackPeak
                else -> info?.trackPeak ?: info?.albumPeak
            } ?: 1f
            var targetDb = (gainDb ?: fallback) + preamp
            if (preventClip && peak > 0f) {
                val maxDb = 20f * (kotlin.math.log10(1f / peak))
                if (targetDb > maxDb) targetDb = maxDb
            }
            val ampDbForPlayer = if (allowBoost) targetDb.coerceAtMost(0f) else targetDb.coerceAtMost(0f)
            val amp = Math.pow(10.0, (ampDbForPlayer / 20f).toDouble()).toFloat()
            val remainingBoostDb = if (allowBoost) (targetDb - ampDbForPlayer) else 0f
            val leMb = if (remainingBoostDb > 0.05f) (remainingBoostDb * 100f).toInt() else 0

            val sb = StringBuilder()
            sb.appendLine("ReplayGain enabled: ${enabled}")
            sb.appendLine("Mode: ${mode}")
            sb.appendLine("Tag track gain: ${info?.trackGainDb?.let { String.format("%.2f dB", it) } ?: "(none)"}")
            sb.appendLine("Tag album gain: ${info?.albumGainDb?.let { String.format("%.2f dB", it) } ?: "(none)"}")
            sb.appendLine("Tag peak: ${info?.trackPeak ?: info?.albumPeak ?: "(none)"}")
            sb.appendLine("Preamp: ${String.format("%.1f dB", preamp)}  Fallback: ${String.format("%.1f dB", fallback)}")
            sb.appendLine("Prevent clipping: ${preventClip}  Allow boost: ${allowBoost}")
            sb.appendLine("")
            sb.appendLine("Computed target: ${String.format("%.2f dB", targetDb)}")
            sb.appendLine("Player volume factor: ${String.format("%.3f", amp)}")
            if (allowBoost) sb.appendLine("LoudnessEnhancer boost: ${leMb} mB")

            androidx.appcompat.app.AlertDialog.Builder(this)
                .setTitle("ReplayGain info")
                .setMessage(sb.toString())
                .setPositiveButton("OK", null)
                .show()
        } catch (_: Exception) {
            showVisualFeedback("Failed to load ReplayGain info")
        }
    }
    
    private fun showLyrics() {
        val song = currentSong ?: return
        // Try to find a .lrc next to the file path when path is a file
        val path = song.path
        var lrcContent: String? = null
        try {
            if (!path.startsWith("content://")) {
                val file = java.io.File(path)
                val lrc = java.io.File(file.parentFile, file.nameWithoutExtension + ".lrc")
                if (lrc.exists()) {
                    lrcContent = lrc.readText()
                }
            }
        } catch (_: Exception) {}
        if (lrcContent.isNullOrBlank()) {
            showVisualFeedback("No lyrics file found")
            return
        }
        val lines = com.stash.opusplayer.utils.LrcParser.parse(lrcContent)
        if (lines.isEmpty()) {
            showVisualFeedback("No timed lyrics found")
            return
        }
        val dialog = androidx.appcompat.app.AlertDialog.Builder(this).create()
        val container = android.widget.ScrollView(this)
        val tv = android.widget.TextView(this).apply {
            setPadding(32, 32, 32, 32)
            textSize = 16f
        }
        container.addView(tv)
        dialog.setView(container)
        dialog.setTitle("Lyrics")
        dialog.setButton(androidx.appcompat.app.AlertDialog.BUTTON_POSITIVE, "Close") { d, _ -> d.dismiss() }
        dialog.show()
        // Update every 500ms to highlight current line
        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        val runnable = object : Runnable {
            override fun run() {
                val pos = mediaController?.currentPosition ?: 0L
                val idx = lines.indexOfLast { it.timeMs <= pos }.coerceAtLeast(0)
                val display = buildString {
                    lines.forEachIndexed { i, l ->
                        if (i == idx) append("\u25CF ") else append("  ")
                        append(l.text).append('\n')
                    }
                }
                tv.text = display
                handler.postDelayed(this, 500)
            }
        }
        dialog.setOnDismissListener { handler.removeCallbacksAndMessages(null) }
        handler.post(runnable)
    }

    private fun toggleAbRepeat() {
        try {
            val prefs = getSharedPreferences("ab_repeat", 0)
            val current = prefs.getBoolean("ab_enabled", false)
            val next = !current
            prefs.edit().putBoolean("ab_enabled", next).apply()
            mediaController?.sendCustomCommand(
                androidx.media3.session.SessionCommand("SET_AB_ENABLED", android.os.Bundle.EMPTY),
                androidx.core.os.bundleOf("enabled" to next)
            )
            showVisualFeedback(if (next) "A-B Repeat ON" else "A-B Repeat OFF")
        } catch (_: Exception) {}
    }

    private fun sendAbSetPoint(action: String) {
        try {
            val pos = mediaController?.currentPosition ?: 0L
            val extras = android.os.Bundle().apply { putLong("position_ms", pos) }
            mediaController?.sendCustomCommand(
                androidx.media3.session.SessionCommand(action, android.os.Bundle.EMPTY),
                extras
            )
            val label = if (action == "SET_AB_A") "Set A" else "Set B"
            showVisualFeedback("$label at ${formatTime(pos)}")
        } catch (_: Exception) {}
    }

    private fun sendAbClear() {
        try {
            mediaController?.sendCustomCommand(
                androidx.media3.session.SessionCommand("CLEAR_AB", android.os.Bundle.EMPTY),
                android.os.Bundle.EMPTY
            )
            showVisualFeedback("A-B points cleared")
        } catch (_: Exception) {}
    }

    private fun showSleepTimerDialog() {
        val options = arrayOf("End of track", "15 minutes", "30 minutes", "45 minutes", "60 minutes", "Cancel timer")
        androidx.appcompat.app.AlertDialog.Builder(this)
            .setTitle("Sleep Timer")
            .setItems(options) { dialog, which ->
                when (which) {
                    0 -> { // End of track
                        val dur = (mediaController?.duration ?: 0L)
                        val pos = (mediaController?.currentPosition ?: 0L)
                        val remain = if (dur > 0L) (dur - pos).coerceAtLeast(0L) else 0L
                        if (remain > 0L) sendSleepTimerCommand(remain) else showVisualFeedback("Unknown track length")
                    }
                    1 -> sendSleepTimerCommand(15 * 60_000L)
                    2 -> sendSleepTimerCommand(30 * 60_000L)
                    3 -> sendSleepTimerCommand(45 * 60_000L)
                    4 -> sendSleepTimerCommand(60 * 60_000L)
                    5 -> cancelSleepTimerCommand()
                }
            }
            .setNegativeButton("Close", null)
            .show()
    }

    private fun sendSleepTimerCommand(durationMs: Long) {
        try {
            val extras = android.os.Bundle().apply { putLong("duration_ms", durationMs) }
            mediaController?.sendCustomCommand(
                androidx.media3.session.SessionCommand("SET_SLEEP_TIMER", android.os.Bundle.EMPTY),
                extras
            )
            showVisualFeedback("Sleep timer set")
        } catch (_: Exception) {}
    }

    private fun cancelSleepTimerCommand() {
        try {
            mediaController?.sendCustomCommand(
                androidx.media3.session.SessionCommand("CANCEL_SLEEP_TIMER", android.os.Bundle.EMPTY),
                android.os.Bundle.EMPTY
            )
            showVisualFeedback("Sleep timer canceled")
        } catch (_: Exception) {}
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
            showVisualFeedback("No artwork available")
            return
        }
        val baos = java.io.ByteArrayOutputStream()
        artBitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, baos)
        val jpegBytes = baos.toByteArray()
        
        lifecycleScope.launch(kotlinx.coroutines.Dispatchers.IO) {
            val ok = when (ext) {
"mp3" -> com.stash.opusplayer.utils.TagEditor.embedArtworkMp3(this@NowPlayingActivity, path, jpegBytes)
else -> com.stash.opusplayer.utils.TagEditor.embedArtworkAny(this@NowPlayingActivity, path, jpegBytes)
            }
            launch(kotlinx.coroutines.Dispatchers.Main) {
                if (ok) {
                    showVisualFeedback("Artwork embedded ✓")
                } else {
                    showVisualFeedback("Failed to embed artwork")
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
                            showVisualFeedback("-10s")
                        }
                        touchX > rightThird -> {
                            // Right side - seek forward 10 seconds
                            val currentPos = controller.currentPosition
                            val duration = controller.duration
                            val newPos = (currentPos + 10000).coerceAtMost(duration)
                            controller.seekTo(newPos)
                            showVisualFeedback("+10s")
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
            
            // Connect EnhancedSynthWave to the media controller's audio session
            try {
                mediaController?.let { controller ->
                    val audioSessionId = controller.audioAttributes?.let { 
                        // Try to get audio session ID from the controller
                        if (controller is androidx.media3.exoplayer.ExoPlayer) {
                            controller.audioSessionId
                        } else {
                            0 // Fall back to global session
                        }
                    } ?: 0
                    binding.enhancedSynthWaveView.setAudioSession(audioSessionId)
                }
            } catch (e: Exception) {
                android.util.Log.w("NowPlayingActivity", "Could not connect EnhancedSynthWave to audio session", e)
            }
        }, MoreExecutors.directExecutor())
    }
    
    private fun setupPlayerManager() {
        musicPlayerManager = (application as com.stash.opusplayer.StashWaveApplication).playerManager
        
        // Observe player state changes (shared manager)
        lifecycleScope.launch {
            musicPlayerManager?.currentSong?.collect { song ->
                if (song != null) {
                    currentSong = song
                    displaySongInfo(song)
                } else {
                    // Fallback to controller metadata to keep art/text fresh
                    setArtworkFromMetadata()
                    updateMediaInfo()
                }
            }
        }
        
        lifecycleScope.launch {
            musicPlayerManager?.isPlaying?.collect { isPlaying ->
                updatePlayPauseButton(isPlaying)
                if (isPlaying) startProgressUpdates() else stopProgressUpdates()
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

            override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
                try {
                    android.util.Log.e("NowPlayingActivity", "Player error: code=${error.errorCode} msg=${error.message}", error)
                    showVisualFeedback("Playback error")
                } catch (_: Exception) {}
            }
            
            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                updateMediaInfo()
                // Ensure artwork & metadata panel update on every track change
                setArtworkFromMetadata()
                if (binding.metadataContainer.visibility == android.view.View.VISIBLE) {
                    populateMetadata()
                }
                // Show RG badge (brief) if enabled
                showReplayGainBadgeIfEnabled()
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
        
        // Auto-embed artwork into MP3 on first play if enabled and embedded art is missing
        tryAutoEmbedArtworkIfEnabled(song, cached, embedded)
        
        updateFavoriteButton(song.isFavorite)
        // Attempt to show RG badge if enabled and controller ready
        showReplayGainBadgeIfEnabled()
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
                    com.stash.opusplayer.utils.TagEditor.embedArtworkMp3(this@NowPlayingActivity, song.path, jpeg)
                } else {
                    com.stash.opusplayer.utils.TagEditor.embedArtworkAny(this@NowPlayingActivity, song.path, jpeg)
                }
            }
        } catch (_: Exception) {}
    }
    
    private fun setDefaultArtwork() {
        Glide.with(this)
            .load(R.drawable.ic_music_note)
            .into(binding.albumArtwork)
    }
    
    private fun setArtworkFromMetadata() {
        try {
            val controller = mediaController ?: return
            val title = controller.mediaMetadata.title?.toString() ?: return
            val artist = controller.mediaMetadata.artist?.toString() ?: ""
            val album = controller.mediaMetadata.albumTitle?.toString() ?: ""
            val fakeSong = com.stash.opusplayer.data.Song(
                id = 0L,
                title = title,
                artist = artist,
                album = album,
                duration = controller.duration.takeIf { it > 0 } ?: 0L,
                path = ""
            )
            val cache = com.stash.opusplayer.artwork.ArtworkCache(this)
            val bmp = cache.loadBitmapIfPresent(fakeSong, 512)
            if (bmp != null) {
                Glide.with(this)
                    .load(bmp)
                    .centerCrop()
                    .into(binding.albumArtwork)
                try {
                    Glide.with(this)
                        .load(bmp)
                        .apply(com.bumptech.glide.request.RequestOptions.bitmapTransform(jp.wasabeef.glide.transformations.BlurTransformation(25, 3)))
                        .into(binding.backdropImage)
                } catch (_: Exception) {}
            }
        } catch (_: Exception) {
            // ignore
        }
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
                mediaController?.let { controller ->
                    val currentPos = controller.currentPosition
                    val duration = controller.duration
                    updateSeekBar(currentPos, duration)
                    
                    // Update EnhancedSynthWave progress
                    try {
                        binding.enhancedSynthWaveView.updateProgress(currentPos, duration)
                    } catch (e: Exception) {
                        android.util.Log.w("NowPlayingActivity", "Error updating EnhancedSynthWave progress", e)
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
    
    private fun toggleMetadataView() {
        if (binding.metadataContainer.visibility == android.view.View.VISIBLE) {
            hideMetadataView()
        } else {
            showMetadataView()
        }
    }
    
    private fun showMetadataView() {
        // Hide secondary controls
        binding.secondaryControlsContainer.visibility = android.view.View.GONE
        
        // Show metadata container
        binding.metadataContainer.visibility = android.view.View.VISIBLE
        
        // Populate metadata
        populateMetadata()
    }
    
    private fun showQueueDialog() {
        val mgr = (application as? com.stash.opusplayer.StashWaveApplication)?.playerManager
        val list = mgr?.playlist?.value ?: emptyList()
        if (list.isEmpty()) {
            showVisualFeedback("Queue is empty")
            return
        }
        val currentIndex = mgr?.currentIndex?.value ?: 0
        val titles = list.mapIndexed { index, s ->
            val mark = if (index == currentIndex) "• " else ""
            "$mark${s.displayName} — ${s.artistName}"
        }.toTypedArray()
        androidx.appcompat.app.AlertDialog.Builder(this)
            .setTitle("Queue (${list.size})")
            .setItems(titles) { _, which ->
                mgr?.playFromPlaylist(which)
            }
            .setNegativeButton("Close", null)
            .show()
    }

    private fun hideMetadataView() {
        // Hide metadata container
        binding.metadataContainer.visibility = android.view.View.GONE
        
        // Show secondary controls
        binding.secondaryControlsContainer.visibility = android.view.View.VISIBLE
    }
    
    private fun populateMetadata() {
        currentSong?.let { song ->
            // Set basic info immediately
            binding.metadataFileNameValue.text = java.io.File(song.path).name
            binding.metadataDurationValue.text = formatTime(song.duration)
            binding.metadataPathValue.text = song.path
            
            // Default values while loading
            binding.metadataBitrateValue.text = "Loading..."
            binding.metadataSampleRateValue.text = "Loading..."
            binding.metadataFormatValue.text = "Loading..."
            
            // Load from cache or extract in background (silently)
            lifecycleScope.launch(kotlinx.coroutines.Dispatchers.IO) {
                try {
                    val repository = com.stash.opusplayer.data.MusicRepository(this@NowPlayingActivity)
                    var metadata = repository.metadataDao.getMetadata(song.path)
                    
                    // If not cached or outdated, extract metadata
                    if (metadata == null || metadata.hasErrors || isMetadataOutdated(metadata)) {
                        // Schedule background metadata scanning for this file
                        com.stash.opusplayer.work.MetadataScanWorker.scheduleMetadataScan(
                            this@NowPlayingActivity,
                            listOf(song.path)
                        )
                        
                        // Try to extract immediately for current display
                        metadata = extractMetadataQuietly(song.path)
                    }
                    
                    launch(kotlinx.coroutines.Dispatchers.Main) {
                        metadata?.let { meta ->
                            // Bitrate
                            binding.metadataBitrateValue.text = if (meta.bitrate > 0) {
                                "${meta.bitrate / 1000} kbps"
                            } else {
                                "Unknown"
                            }
                            
                            // Sample rate
                            binding.metadataSampleRateValue.text = if (meta.sampleRate > 0) {
                                "${meta.sampleRate} Hz"
                            } else {
                                "Unknown"
                            }
                            
                            // Format
                            binding.metadataFormatValue.text = if (meta.format.isNotBlank()) {
                                meta.format
                            } else {
                                song.path.substringAfterLast('.', "Unknown").uppercase()
                            }
                        } ?: run {
                            // Fallback if extraction fails
                            binding.metadataBitrateValue.text = "Unknown"
                            binding.metadataSampleRateValue.text = "Unknown"
                            binding.metadataFormatValue.text = song.path.substringAfterLast('.', "Unknown").uppercase()
                        }
                    }
                } catch (e: Exception) {
                    android.util.Log.e("NowPlayingActivity", "Error loading metadata", e)
                    launch(kotlinx.coroutines.Dispatchers.Main) {
                        binding.metadataBitrateValue.text = "Error"
                        binding.metadataSampleRateValue.text = "Error"
                        binding.metadataFormatValue.text = "Error"
                    }
                }
            }
        }
    }
    
    private fun isMetadataOutdated(metadata: com.stash.opusplayer.data.MetadataInfo): Boolean {
        val file = java.io.File(metadata.filePath)
        if (!file.exists()) return true
        // Check if file was modified since last scan
        return file.lastModified() != metadata.lastModified
    }
    
    private suspend fun extractMetadataQuietly(filePath: String): com.stash.opusplayer.data.MetadataInfo? {
        return try {
            val file = java.io.File(filePath)
            val retriever = android.media.MediaMetadataRetriever()
            
            try {
                if (filePath.startsWith("content://")) {
                    retriever.setDataSource(this, android.net.Uri.parse(filePath))
                } else {
                    retriever.setDataSource(filePath)
                }
                
                val bitrate = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toIntOrNull() ?: 0
                val sampleRate = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_SAMPLERATE)?.toIntOrNull() ?: 0
                val duration = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
                val mimeType = retriever.extractMetadata(android.media.MediaMetadataRetriever.METADATA_KEY_MIMETYPE) ?: ""
                
                val format = when {
                    mimeType.contains("mp3", true) -> "MP3"
                    mimeType.contains("flac", true) -> "FLAC"
                    mimeType.contains("opus", true) -> "Opus"
                    mimeType.contains("ogg", true) -> "OGG"
                    mimeType.contains("m4a", true) || mimeType.contains("mp4", true) -> "M4A"
                    mimeType.contains("wav", true) -> "WAV"
                    mimeType.contains("wma", true) -> "WMA"
                    else -> filePath.substringAfterLast('.', "Unknown").uppercase()
                }
                
                val metadata = com.stash.opusplayer.data.MetadataInfo(
                    filePath = filePath,
                    fileName = file.name,
                    duration = duration,
                    bitrate = bitrate,
                    sampleRate = sampleRate,
                    format = format,
                    mimeType = mimeType,
                    fileSize = if (file.exists()) file.length() else 0L,
                    lastModified = if (file.exists()) file.lastModified() else 0L,
                    hasErrors = false
                )
                
                // Cache it for next time (silently)
                val repository = com.stash.opusplayer.data.MusicRepository(this)
                repository.metadataDao.insertMetadata(metadata)
                
                metadata
                
            } finally {
                retriever.release()
            }
        } catch (e: Exception) {
            android.util.Log.w("NowPlayingActivity", "Silent metadata extraction failed for $filePath", e)
            null
        }
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
        // Do NOT release the shared MusicPlayerManager here — it's a singleton managed by the Application.
        // Releasing it would drop the MediaController connection app-wide and break playback.
        mediaController?.release()
    }
}
