package com.stash.opusplayer.ui.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.appcompat.app.AlertDialog
import com.stash.opusplayer.databinding.FragmentFavoritesBinding
import com.stash.opusplayer.data.MusicRepository
import com.stash.opusplayer.data.Song
import com.stash.opusplayer.ui.MainActivity
import com.stash.opusplayer.ui.adapters.SongAdapter
import com.stash.opusplayer.utils.MetadataExtractor
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay

class FavoritesFragment : Fragment() {
    
    private var _binding: FragmentFavoritesBinding? = null
    private val binding get() = _binding!!
    
    private lateinit var songAdapter: SongAdapter
    private lateinit var musicRepository: MusicRepository
    private lateinit var metadataExtractor: MetadataExtractor
    private var allFavorites: List<Song> = emptyList()
    
    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentFavoritesBinding.inflate(inflater, container, false)
        return binding.root
    }
    
    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        
        musicRepository = MusicRepository(requireContext())
        metadataExtractor = MetadataExtractor(requireContext())
        setupRecyclerView()
        setupSearchButton()
        loadFavorites()
    }
    
    private fun setupRecyclerView() {
        songAdapter = SongAdapter(
            onSongClick = { song ->
                val list = songAdapter.currentList
                val index = list.indexOfFirst { it.id == song.id }.let { if (it >= 0) it else 0 }
                (activity as? MainActivity)?.playSongsStartingFrom(list, index, "Liked Songs")
            },
            onFavoriteToggle = { song ->
                (activity as? MainActivity)?.toggleFavorite(song)
                viewLifecycleOwner.lifecycleScope.launch {
                    delay(500)
                    loadFavorites()
                }
            },
            onAddToPlaylist = { song ->
                (activity as? MainActivity)?.addToPlaylist(song)
            },
            onPlayNext = { song -> (activity as? MainActivity)?.playNext(song) },
            onAddToQueue = { song -> (activity as? MainActivity)?.addToQueueTail(song) },
            metadataExtractor = metadataExtractor
        )
        
        binding.recyclerView.apply {
            adapter = songAdapter
            layoutManager = LinearLayoutManager(requireContext())
        }
    }
    
    private fun setupSearchButton() {
        binding.searchButton.setOnClickListener { view ->
            // Add visual feedback
            view.animate()
                .scaleX(0.9f)
                .scaleY(0.9f)
                .setDuration(100)
                .withEndAction {
                    view.animate()
                        .scaleX(1f)
                        .scaleY(1f)
                        .setDuration(100)
                        .start()
                }
                .start()
            showSearchDialog()
        }
    }
    
    private fun showSearchDialog() {
        val searchView = EditText(requireContext()).apply {
            hint = "Search favorites..."
            setPadding(32, 16, 32, 16)
        }
        
        AlertDialog.Builder(requireContext())
            .setTitle("Search Favorites")
            .setView(searchView)
            .setPositiveButton("Search") { _, _ ->
                val query = searchView.text.toString().trim()
                if (query.isNotEmpty()) {
                    searchFavorites(query)
                } else {
                    // Show all favorites if query is empty
                    songAdapter.submitList(allFavorites)
                }
            }
            .setNegativeButton("Show All") { _, _ ->
                // Reset to show all favorites
                songAdapter.submitList(allFavorites)
                updateEmptyState()
            }
            .setNeutralButton("Cancel", null)
            .show()
            
        // Focus the search field and show keyboard
        searchView.requestFocus()
    }
    
    private fun searchFavorites(query: String) {
        // Show searching state
        binding.emptyStateText.text = "Searching favorites..."
        binding.emptyStateContainer.visibility = View.VISIBLE
        binding.recyclerView.visibility = View.GONE
        
        viewLifecycleOwner.lifecycleScope.launch {
            // Add small delay to show search feedback
            delay(200)
            
            val filteredSongs = allFavorites.filter { song ->
                song.title.contains(query, ignoreCase = true) ||
                song.artist.contains(query, ignoreCase = true) ||
                song.album.contains(query, ignoreCase = true)
            }
            
            songAdapter.submitList(filteredSongs)
            
            // Update empty state based on search results
            if (filteredSongs.isEmpty()) {
                binding.recyclerView.visibility = View.GONE
                binding.emptyStateText.text = "No favorites found for \"$query\"\n\n💡 Try different keywords or add more songs to favorites!"
                binding.emptyStateContainer.visibility = View.VISIBLE
                
                // Show helpful toast
                android.widget.Toast.makeText(
                    requireContext(),
                    "No results for \"$query\" in favorites",
                    android.widget.Toast.LENGTH_SHORT
                ).show()
            } else {
                binding.recyclerView.visibility = View.VISIBLE
                binding.emptyStateContainer.visibility = View.GONE
                
                // Show results count
                android.widget.Toast.makeText(
                    requireContext(),
                    "Found ${filteredSongs.size} favorite${if (filteredSongs.size != 1) "s" else ""}",
                    android.widget.Toast.LENGTH_SHORT
                ).show()
            }
        }
    }
    
    private fun loadFavorites() {
        viewLifecycleOwner.lifecycleScope.launch {
            try {
                musicRepository.getFavorites().collect { favorites ->
                    allFavorites = favorites
                    
                    val b = _binding ?: return@collect
                    if (favorites.isNotEmpty()) {
                        songAdapter.submitList(favorites)
                        b.recyclerView.visibility = View.VISIBLE
                        b.emptyStateContainer.visibility = View.GONE
                    } else {
                        b.recyclerView.visibility = View.GONE
                        b.emptyStateText.text = "No liked songs yet\n\n💡 Tap the heart icon on any song to add it here!"
                        b.emptyStateContainer.visibility = View.VISIBLE
                    }
                }
                (activity as? MainActivity)?.notifyContentLoaded()
            } catch (e: Exception) {
                val b = _binding ?: return@launch
                b.recyclerView.visibility = View.GONE
                b.emptyStateText.text = "Error loading favorites\n${e.message}"
                b.emptyStateContainer.visibility = View.VISIBLE
                (activity as? MainActivity)?.notifyContentLoaded()
            }
        }
    }
    
    private fun updateEmptyState() {
        val b = _binding ?: return
        if (allFavorites.isEmpty()) {
            b.recyclerView.visibility = View.GONE
            b.emptyStateText.text = "No liked songs yet\n\n💡 Tap the heart icon on any song to add it here!"
            b.emptyStateContainer.visibility = View.VISIBLE
        } else {
            b.recyclerView.visibility = View.VISIBLE
            b.emptyStateContainer.visibility = View.GONE
        }
    }
    
    override fun onResume() {
        super.onResume()
        // Refresh favorites when returning to this screen
        loadFavorites()
    }
    
    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
