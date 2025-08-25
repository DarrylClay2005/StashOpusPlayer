package com.stash.opusplayer.ui.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.LinearLayoutManager
import com.stash.opusplayer.databinding.FragmentMusicLibraryBinding
import com.stash.opusplayer.data.MusicRepository
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
        songAdapter = SongAdapter { song ->
            // Handle song click - play the song
            // TODO: Implement playback
        }
        
        binding.recyclerView.apply {
            adapter = songAdapter
            layoutManager = LinearLayoutManager(requireContext())
        }
    }
    
    private fun loadSongs() {
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val songs = musicRepository.getAllSongs()
                if (songs.isNotEmpty()) {
                    songAdapter.submitList(songs)
                    binding.recyclerView.visibility = View.VISIBLE
                    binding.emptyStateText.visibility = View.GONE
                } else {
                    binding.recyclerView.visibility = View.GONE
                    binding.emptyStateText.visibility = View.VISIBLE
                }
            } catch (e: Exception) {
                binding.recyclerView.visibility = View.GONE
                binding.emptyStateText.visibility = View.VISIBLE
            }
        }
    }
    
    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
