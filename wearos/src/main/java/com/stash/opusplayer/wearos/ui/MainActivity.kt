package com.stash.opusplayer.wearos.ui

import android.content.Intent
import android.os.Bundle
import android.view.View
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.bumptech.glide.Glide
import com.stash.opusplayer.wearos.R
import com.stash.opusplayer.wearos.databinding.ActivityMainBinding
import com.stash.opusplayer.wearos.repository.WearMusicRepository
import com.stash.opusplayer.wearos.viewmodel.WearMusicViewModel
import kotlinx.coroutines.launch

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private lateinit var repository: WearMusicRepository
    private val viewModel: WearMusicViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        repository = WearMusicRepository.getInstance(this)
        
        setupUI()
        observeData()
        
        // Request initial data from phone
        lifecycleScope.launch {
            repository.requestInitialData()
        }
    }

    private fun setupUI() {
        // Playback controls
        binding.playPauseButton.setOnClickListener {
            lifecycleScope.launch {
                val playbackState = viewModel.playbackState.value
                if (playbackState?.isPlaying == true) {
                    repository.sendPauseCommand()
                } else {
                    repository.sendPlayCommand()
                }
            }
        }

        binding.previousButton.setOnClickListener {
            lifecycleScope.launch {
                repository.sendPreviousCommand()
            }
        }

        binding.nextButton.setOnClickListener {
            lifecycleScope.launch {
                repository.sendNextCommand()
            }
        }

        // Navigation buttons
        binding.tracksButton.setOnClickListener {
            val intent = Intent(this, TrackListActivity::class.java)
            startActivity(intent)
        }

        binding.phoneAppButton.setOnClickListener {
            lifecycleScope.launch {
                repository.sendOpenPhoneAppCommand()
            }
        }

        // Tap on album art to open full player
        binding.albumArt.setOnClickListener {
            val intent = Intent(this, PlayerActivity::class.java)
            startActivity(intent)
        }
    }

    private fun observeData() {
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                launch {
                    viewModel.isPhoneConnected.collect { connected ->
                        updateConnectionStatus(connected)
                    }
                }

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
            }
        }
    }

    private fun updateConnectionStatus(connected: Boolean) {
        if (connected) {
            binding.connectionStatusLayout.visibility = View.GONE
            binding.currentSongLayout.visibility = View.VISIBLE
            binding.playbackControlsLayout.visibility = View.VISIBLE
            binding.menuLayout.visibility = View.VISIBLE
        } else {
            binding.connectionStatusLayout.visibility = View.VISIBLE
            binding.currentSongLayout.visibility = View.GONE
            binding.playbackControlsLayout.visibility = View.GONE
            binding.menuLayout.visibility = View.GONE
            
            binding.connectionStatusText.text = getString(R.string.phone_not_connected)
        }
    }

    private fun updatePlaybackState(state: com.stash.opusplayer.wearos.data.WearPlaybackState?) {
        if (state == null) return

        // Update play/pause button
        if (state.isPlaying) {
            binding.playPauseButton.setImageResource(R.drawable.ic_pause_24)
            binding.playPauseButton.contentDescription = getString(R.string.pause)
        } else {
            binding.playPauseButton.setImageResource(R.drawable.ic_play_arrow_24)
            binding.playPauseButton.contentDescription = getString(R.string.play)
        }

        // Enable/disable navigation buttons
        binding.previousButton.isEnabled = state.hasPrevious
        binding.nextButton.isEnabled = state.hasNext
        
        binding.previousButton.alpha = if (state.hasPrevious) 1.0f else 0.5f
        binding.nextButton.alpha = if (state.hasNext) 1.0f else 0.5f
    }

    private fun updateCurrentSong(song: com.stash.opusplayer.wearos.data.WearSong?) {
        if (song == null) {
            binding.currentSongLayout.visibility = View.GONE
            return
        }

        binding.currentSongLayout.visibility = View.VISIBLE
        
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
}
