package com.stash.opusplayer.ui.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.stash.opusplayer.databinding.FragmentMusicLibraryBinding
import com.stash.opusplayer.data.MusicRepository
import com.stash.opusplayer.ui.MainActivity
import com.stash.opusplayer.ui.adapters.SongAdapter
import kotlinx.coroutines.*

class MusicLibraryFragment : Fragment() {
    
    private var _binding: FragmentMusicLibraryBinding? = null
    private val binding get() = _binding!!
    
    private lateinit var songAdapter: SongAdapter
    private lateinit var musicRepository: MusicRepository
    
    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentMusicLibraryBinding.inflate(inflater, container, false)
        return binding.root
    }
    
    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        
        musicRepository = MusicRepository(requireContext())
        setupRecyclerView()
        loadSongs()
    }
    
    private fun setupRecyclerView() {
        val metadataExtractor = com.stash.opusplayer.utils.MetadataExtractor(requireContext())
        
        songAdapter = SongAdapter(
            onSongClick = { song ->
                // Handle song click - play the song
                (activity as? MainActivity)?.playMusic(song)
            },
            onFavoriteToggle = { song ->
                // Toggle favorite status
                (activity as? MainActivity)?.toggleFavorite(song)
                // Refresh the list after a short delay, tied to the view lifecycle
                viewLifecycleOwner.lifecycleScope.launch {
                    delay(500)
                    loadSongs()
                }
            },
            onAddToPlaylist = { song ->
                // Add to current playlist
                (activity as? MainActivity)?.addToPlaylist(song)
            },
            metadataExtractor = metadataExtractor
        )
        
        binding.recyclerView.apply {
            adapter = songAdapter
            layoutManager = LinearLayoutManager(requireContext())
        }
    }
    
    private fun loadSongs() {
        viewLifecycleOwner.lifecycleScope.launch {
            try {
                // Fast listing first for quick UI, then full enrich in background
                val fast = musicRepository.getAllSongsFromAllSourcesFast()
                val b = _binding ?: return@launch
                if (fast.isNotEmpty()) {
                    songAdapter.submitList(fast)
                    b.recyclerView.visibility = View.VISIBLE
                    b.emptyStateText.visibility = View.GONE
                } else {
                    b.recyclerView.visibility = View.GONE
                    b.emptyStateText.visibility = View.VISIBLE
                }
                // Background enrichment; update list when done
                launch {
                    val full = musicRepository.getAllSongsFromAllSources()
                    if (_binding != null && full.isNotEmpty()) {
                        songAdapter.submitList(full)
                    }
                }
                (activity as? com.stash.opusplayer.ui.MainActivity)?.notifyContentLoaded()
            } catch (e: Exception) {
                val b = _binding ?: return@launch
                b.recyclerView.visibility = View.GONE
                b.emptyStateText.visibility = View.VISIBLE
                (activity as? com.stash.opusplayer.ui.MainActivity)?.notifyContentLoaded()
            }
        }
    }
    
    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
