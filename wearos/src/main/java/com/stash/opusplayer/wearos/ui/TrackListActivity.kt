package com.stash.opusplayer.wearos.ui

import android.os.Bundle
import android.view.View
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.recyclerview.widget.LinearLayoutManager
import com.stash.opusplayer.wearos.R
import com.stash.opusplayer.wearos.data.WearPlaylist
import com.stash.opusplayer.wearos.data.WearSong
import com.stash.opusplayer.wearos.databinding.ActivityTrackListBinding
import com.stash.opusplayer.wearos.ui.adapter.TrackListAdapter
import com.stash.opusplayer.wearos.viewmodel.WearMusicViewModel
import kotlinx.coroutines.launch

class TrackListActivity : AppCompatActivity() {

    private lateinit var binding: ActivityTrackListBinding
    private val viewModel: WearMusicViewModel by viewModels()
    private lateinit var trackAdapter: TrackListAdapter

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityTrackListBinding.inflate(layoutInflater)
        setContentView(binding.root)

        setupRecyclerView()
        observeData()
    }

    private fun setupRecyclerView() {
        trackAdapter = TrackListAdapter { song ->
            // Play selected song
            viewModel.playSong(song.id)
        }

        binding.tracksRecyclerView.apply {
            layoutManager = LinearLayoutManager(this@TrackListActivity)
            adapter = trackAdapter
        }
    }

    private fun observeData() {
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                launch {
                    viewModel.playlist.collect { playlist ->
                        updatePlaylist(playlist)
                    }
                }

                launch {
                    viewModel.currentSong.collect { currentSong ->
                        trackAdapter.updateCurrentSong(currentSong)
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

    private fun updatePlaylist(playlist: WearPlaylist?) {
        if (playlist == null || playlist.songs.isEmpty()) {
            binding.tracksRecyclerView.visibility = View.GONE
            binding.emptyStateLayout.visibility = View.VISIBLE
            binding.trackCount.text = getString(R.string.no_tracks)
            return
        }

        binding.tracksRecyclerView.visibility = View.VISIBLE
        binding.emptyStateLayout.visibility = View.GONE
        
        val trackCount = playlist.songs.size
        binding.trackCount.text = resources.getQuantityString(
            R.plurals.track_count, 
            trackCount, 
            trackCount
        )

        trackAdapter.updateTracks(playlist.songs)

        // Scroll to current track
        if (playlist.currentIndex >= 0 && playlist.currentIndex < playlist.songs.size) {
            binding.tracksRecyclerView.scrollToPosition(playlist.currentIndex)
        }
    }

    private fun updateConnectionStatus(connected: Boolean) {
        if (!connected) {
            binding.trackCount.text = getString(R.string.phone_not_connected)
            binding.tracksRecyclerView.visibility = View.GONE
            binding.emptyStateLayout.visibility = View.VISIBLE
        }
    }
}
