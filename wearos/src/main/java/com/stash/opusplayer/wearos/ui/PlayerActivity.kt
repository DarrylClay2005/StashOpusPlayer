package com.stash.opusplayer.wearos.ui

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.media3.common.Player
import com.bumptech.glide.Glide
import com.stash.opusplayer.wearos.R
import com.stash.opusplayer.wearos.data.WearPlaybackState
import com.stash.opusplayer.wearos.data.WearSong
import com.stash.opusplayer.wearos.databinding.ActivityPlayerBinding
import com.stash.opusplayer.wearos.viewmodel.WearMusicViewModel
import kotlinx.coroutines.launch

class PlayerActivity : AppCompatActivity() {

    private lateinit var binding: ActivityPlayerBinding
    private val viewModel: WearMusicViewModel by viewModels()
    
    private val progressHandler = Handler(Looper.getMainLooper())
    private var progressRunnable: Runnable? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityPlayerBinding.inflate(layoutInflater)
        setContentView(binding.root)

        setupUI()
        observeData()
    }

    override fun onResume() {
        super.onResume()
        startProgressUpdates()
    }

    override fun onPause() {
        super.onPause()
        stopProgressUpdates()
    }

    private fun setupUI() {
        // Primary playback controls
        binding.playPauseButton.setOnClickListener {
            val playbackState = viewModel.playbackState.value
            if (playbackState?.isPlaying == true) {
                viewModel.pause()
            } else {
                viewModel.play()
            }
        }

        binding.previousButton.setOnClickListener {
            viewModel.previous()
        }

        binding.nextButton.setOnClickListener {
            viewModel.next()
        }

        // Secondary controls
        binding.shuffleButton.setOnClickListener {
            viewModel.toggleShuffle()
        }

        binding.repeatButton.setOnClickListener {
            viewModel.toggleRepeat()
        }

        // Album art click to go back
        binding.albumArt.setOnClickListener {
            finish()
        }
    }

    private fun observeData() {
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                launch {
                    viewModel.playbackState.collect { state ->
                        updatePlaybackState(state)
                    }
                }

                launch {
                    viewModel.currentSong.collect { song ->
                        updateCurrentSong(song)
                    }
                }

                launch {
                    viewModel.isPhoneConnected.collect { connected ->
                        updateConnectionStatus(connected)
                    }
                }
            }
        }
    }

    private fun updatePlaybackState(state: WearPlaybackState?) {
        if (state == null) return

        // Update play/pause button
        if (state.isPlaying) {
            binding.playPauseButton.setImageResource(R.drawable.ic_pause_24)
            binding.playPauseButton.contentDescription = getString(R.string.pause)
            startProgressUpdates()
        } else {
            binding.playPauseButton.setImageResource(R.drawable.ic_play_arrow_24)
            binding.playPauseButton.contentDescription = getString(R.string.play)
            stopProgressUpdates()
        }

        // Update navigation buttons
        binding.previousButton.isEnabled = state.hasPrevious
        binding.nextButton.isEnabled = state.hasNext
        
        binding.previousButton.alpha = if (state.hasPrevious) 1.0f else 0.5f
        binding.nextButton.alpha = if (state.hasNext) 1.0f else 0.5f

        // Update shuffle button
        binding.shuffleButton.alpha = if (state.isShuffling) 1.0f else 0.5f

        // Update repeat button
        when (state.repeatMode) {
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

        // Update progress
        updateProgress(state.position, state.duration)
    }

    private fun updateCurrentSong(song: WearSong?) {
        if (song == null) return

        binding.songTitle.text = song.title
        binding.artistName.text = song.artist

        // Load album artwork
        Glide.with(this)
            .load(song.artworkUrl)
            .placeholder(R.drawable.ic_music_note)
            .error(R.drawable.ic_music_note)
            .circleCrop()
            .into(binding.albumArt)
    }

    private fun updateConnectionStatus(connected: Boolean) {
        // Could show a connection indicator here if needed
        // For now, just enable/disable controls
        val alpha = if (connected) 1.0f else 0.5f
        binding.playPauseButton.isEnabled = connected
        binding.previousButton.isEnabled = connected
        binding.nextButton.isEnabled = connected
        binding.shuffleButton.isEnabled = connected
        binding.repeatButton.isEnabled = connected
        
        binding.playPauseButton.alpha = alpha
        if (!connected) {
            binding.previousButton.alpha = alpha
            binding.nextButton.alpha = alpha
            binding.shuffleButton.alpha = alpha
            binding.repeatButton.alpha = alpha
        }
    }

    private fun updateProgress(position: Long, duration: Long) {
        if (duration > 0) {
            val progress = viewModel.calculateProgress(position, duration)
            binding.progressRing.progress = progress
            
            binding.currentTime.text = viewModel.formatTime(position)
            binding.totalTime.text = viewModel.formatTime(duration)
        } else {
            binding.progressRing.progress = 0
            binding.currentTime.text = "0:00"
            binding.totalTime.text = "0:00"
        }
    }

    private fun startProgressUpdates() {
        stopProgressUpdates()
        progressRunnable = object : Runnable {
            override fun run() {
                val state = viewModel.playbackState.value
                if (state != null && state.isPlaying) {
                    // Simulate progress update (in real app, this would come from repository)
                    val estimatedPosition = state.position + 1000 // Add 1 second
                    updateProgress(estimatedPosition, state.duration)
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

    override fun onDestroy() {
        super.onDestroy()
        stopProgressUpdates()
    }
}
