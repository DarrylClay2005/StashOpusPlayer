package com.stash.stashwave.ui.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.appcompat.app.AlertDialog
import com.stash.stashwave.databinding.FragmentMusicLibraryBinding
import com.stash.stashwave.data.MusicRepository
import com.stash.stashwave.data.Song
import com.stash.stashwave.ui.MainActivity
import com.stash.stashwave.ui.adapters.SongAdapter
import kotlinx.coroutines.*

class MusicLibraryFragment : Fragment() {
    
    private var _binding: FragmentMusicLibraryBinding? = null
    private val binding get() = _binding!!
    
    private lateinit var songAdapter: SongAdapter
    private lateinit var musicRepository: MusicRepository
    private var allSongs: List<Song> = emptyList()
    
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
        setupSearchButton()
        setupLikedButton()
        loadSongs()
    }
    
    private fun setupRecyclerView() {
val metadataExtractor = com.stash.stashwave.utils.MetadataExtractor(requireContext())
        
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
    
    private fun setupSearchButton() {
        binding.searchButton.setOnClickListener {
            showSearchDialog()
        }
    }
    
    private fun setupLikedButton() {
        binding.likedButton.setOnClickListener {
            // Navigate to Liked Songs fragment
            (activity as? MainActivity)?.let { mainActivity ->
val favoritesFragment = com.stash.stashwave.ui.fragments.FavoritesFragment()
                mainActivity.supportFragmentManager.beginTransaction()
.replace(com.stash.stashwave.R.id.main_content, favoritesFragment)
                    .addToBackStack(null)
                    .commit()
                mainActivity.supportActionBar?.title = "Liked Songs"
            }
        }
    }
    
    private fun showSearchDialog() {
        val searchView = EditText(requireContext()).apply {
            hint = "Search songs..."
            setPadding(32, 16, 32, 16)
        }
        
        AlertDialog.Builder(requireContext())
            .setTitle("Search Music")
            .setView(searchView)
            .setPositiveButton("Search") { _, _ ->
                val query = searchView.text.toString().trim()
                if (query.isNotEmpty()) {
                    searchSongs(query)
                } else {
                    // Show all songs if query is empty
                    songAdapter.submitList(allSongs)
                }
            }
            .setNegativeButton("Show All") { _, _ ->
                // Reset to show all songs
                songAdapter.submitList(allSongs)
            }
            .setNeutralButton("Cancel", null)
            .show()
            
        // Focus the search field and show keyboard
        searchView.requestFocus()
    }
    
    private fun searchSongs(query: String) {
        val filteredSongs = allSongs.filter { song ->
            song.title.contains(query, ignoreCase = true) ||
            song.artist.contains(query, ignoreCase = true) ||
            song.album.contains(query, ignoreCase = true)
        }
        
        songAdapter.submitList(filteredSongs)
        
        // Update empty state based on search results
        if (filteredSongs.isEmpty()) {
            binding.recyclerView.visibility = View.GONE
            binding.emptyStateText.text = "No songs found for \"$query\""
            binding.emptyStateContainer.visibility = View.VISIBLE
        } else {
            binding.recyclerView.visibility = View.VISIBLE
            binding.emptyStateContainer.visibility = View.GONE
        }
    }
    
    private fun loadSongs() {
        viewLifecycleOwner.lifecycleScope.launch {
            try {
                // Fast listing first for quick UI, then full enrich in background
                val fast = musicRepository.getAllSongsFromAllSourcesFast()
                val b = _binding ?: return@launch
                if (fast.isNotEmpty()) {
                    allSongs = fast
                    songAdapter.submitList(fast)
                    b.recyclerView.visibility = View.VISIBLE
                    b.emptyStateContainer.visibility = View.GONE
                } else {
                    b.recyclerView.visibility = View.GONE
                    b.emptyStateText.text = "No music found"
                    b.emptyStateContainer.visibility = View.VISIBLE
                }
                // Background enrichment; update list when done
                launch {
                    val full = musicRepository.getAllSongsFromAllSources()
                    if (_binding != null && full.isNotEmpty()) {
                        allSongs = full
                        songAdapter.submitList(full)
                    }
                }
(activity as? com.stash.stashwave.ui.MainActivity)?.notifyContentLoaded()
            } catch (e: Exception) {
                val b = _binding ?: return@launch
                b.recyclerView.visibility = View.GONE
                b.emptyStateText.visibility = View.VISIBLE
(activity as? com.stash.stashwave.ui.MainActivity)?.notifyContentLoaded()
            }
        }
    }
    
    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
