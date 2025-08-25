package com.stash.opusplayer.ui.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.stash.opusplayer.databinding.FragmentArtistsBinding
import com.stash.opusplayer.data.MusicRepository
import com.stash.opusplayer.ui.adapters.ArtistAdapter
import kotlinx.coroutines.launch

class ArtistsFragment : Fragment() {
    
    private var _binding: FragmentArtistsBinding? = null
    private val binding get() = _binding!!
    
    private lateinit var artistAdapter: ArtistAdapter
    private lateinit var musicRepository: MusicRepository
    
    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentArtistsBinding.inflate(inflater, container, false)
        return binding.root
    }
    
    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        
        musicRepository = MusicRepository(requireContext())
        setupRecyclerView()
        loadArtists()
    }
    
    private fun setupRecyclerView() {
        artistAdapter = ArtistAdapter { artist ->
            // Navigate to artist songs
            showArtistSongs(artist)
        }
        
        binding.recyclerView.apply {
            adapter = artistAdapter
            layoutManager = LinearLayoutManager(requireContext())
        }
    }
    
    private fun loadArtists() {
        lifecycleScope.launch {
            try {
                val songsByArtist = musicRepository.getSongsByArtist()
                if (songsByArtist.isNotEmpty()) {
                    // Convert to list of artist info
                    val artistList = songsByArtist.map { (artist, songs) ->
                        ArtistInfo(
                            name = artist,
                            songCount = songs.size,
                            songs = songs
                        )
                    }.sortedBy { it.name }
                    
                    artistAdapter.submitList(artistList)
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
    
    private fun showArtistSongs(artist: ArtistInfo) {
        // Create a new fragment to show songs by this artist
        val fragment = ArtistSongsFragment.newInstance(artist.name, ArrayList(artist.songs))
        parentFragmentManager.beginTransaction()
            .replace(android.R.id.content, fragment)
            .addToBackStack(null)
            .commit()
    }
    
    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}

data class ArtistInfo(
    val name: String,
    val songCount: Int,
    val songs: List<com.stash.opusplayer.data.Song>
)
