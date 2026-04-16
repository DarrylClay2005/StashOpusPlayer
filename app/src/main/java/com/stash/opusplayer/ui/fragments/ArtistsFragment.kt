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
import com.stash.opusplayer.ui.appearance.ThemeManager
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
        applyAdaptiveChrome()
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
            clipToPadding = false
            setPadding(0, ThemeManager.scaleDp(requireContext(), 4), 0, ThemeManager.scaleDp(requireContext(), 28))
        }
    }

    private fun applyAdaptiveChrome() {
        val context = requireContext()
        val outerPadding = ThemeManager.scaleDp(context, 10)

        binding.root.setPadding(outerPadding, outerPadding, outerPadding, outerPadding)
        binding.artistsHeaderTitle.textSize = ThemeManager.scaleSp(context, 16f)
        binding.artistsHeaderIcon.layoutParams = binding.artistsHeaderIcon.layoutParams.apply {
            width = ThemeManager.scaleDp(context, 24)
            height = ThemeManager.scaleDp(context, 24)
        }
        binding.artistsHeader.layoutParams = (binding.artistsHeader.layoutParams as? ViewGroup.MarginLayoutParams)?.apply {
            bottomMargin = ThemeManager.scaleDp(context, 10)
        } ?: binding.artistsHeader.layoutParams
        binding.emptyStateText.textSize = ThemeManager.scaleSp(context, 14f)
        binding.emptyStateText.setPadding(
            ThemeManager.scaleDp(context, 16),
            ThemeManager.scaleDp(context, 16),
            ThemeManager.scaleDp(context, 16),
            ThemeManager.scaleDp(context, 16)
        )
    }
    
    private fun loadArtists() {
        viewLifecycleOwner.lifecycleScope.launch {
            try {
                val songsByArtist = musicRepository.getSongsByArtist()
                // Basic AI-like normalization: collapse Unknowns, trim whitespace
                val normalized = songsByArtist.mapKeys { (artist, _) ->
                    artist.trim().ifBlank { "Unknown Artist" }
                }
                val b = _binding ?: return@launch
                if (songsByArtist.isNotEmpty()) {
                    // Convert to list of artist info
                    val artistList = normalized.map { (artist, songs) ->
                        ArtistInfo(
                            name = artist,
                            songCount = songs.size,
                            songs = songs
                        )
                    }.sortedBy { it.name.lowercase() }
                    
                    artistAdapter.submitList(artistList)
                    b.recyclerView.visibility = View.VISIBLE
                    b.emptyStateText.visibility = View.GONE
                } else {
                    b.recyclerView.visibility = View.GONE
                    b.emptyStateText.visibility = View.VISIBLE
                }
            } catch (e: Exception) {
                val b = _binding ?: return@launch
                b.recyclerView.visibility = View.GONE
                b.emptyStateText.visibility = View.VISIBLE
            }
        }
    }
    
    private fun showArtistSongs(artist: ArtistInfo) {
        // Create a new fragment to show songs by this artist
        val fragment = ArtistSongsFragment.newInstance(artist.name, ArrayList(artist.songs))
        parentFragmentManager.beginTransaction()
            .replace(com.stash.opusplayer.R.id.main_content, fragment)
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
