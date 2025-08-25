package com.stash.opusplayer.ui.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.stash.opusplayer.data.Song
import com.stash.opusplayer.databinding.FragmentArtistSongsBinding
import com.stash.opusplayer.ui.MainActivity
import com.stash.opusplayer.ui.adapters.SongAdapter
import com.stash.opusplayer.utils.MetadataExtractor
import kotlinx.coroutines.launch

class ArtistSongsFragment : Fragment() {
    
    private var _binding: FragmentArtistSongsBinding? = null
    private val binding get() = _binding!!
    
    private lateinit var songAdapter: SongAdapter
    private lateinit var metadataExtractor: MetadataExtractor
    
    private var artistName: String = ""
    private var songs: List<Song> = emptyList()
    
    companion object {
        private const val ARG_ARTIST_NAME = "artist_name"
        private const val ARG_SONGS = "songs"
        
        fun newInstance(artistName: String, songs: ArrayList<Song>): ArtistSongsFragment {
            val fragment = ArtistSongsFragment()
            val args = Bundle().apply {
                putString(ARG_ARTIST_NAME, artistName)
                putParcelableArrayList(ARG_SONGS, songs)
            }
            fragment.arguments = args
            return fragment
        }
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        arguments?.let {
            artistName = it.getString(ARG_ARTIST_NAME, "")
            songs = it.getParcelableArrayList<Song>(ARG_SONGS) ?: emptyList()
        }
    }
    
    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentArtistSongsBinding.inflate(inflater, container, false)
        return binding.root
    }
    
    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        
        metadataExtractor = MetadataExtractor(requireContext())
        setupRecyclerView()
        loadSongs()
    }
    
    private fun setupRecyclerView() {
        songAdapter = SongAdapter(
            onSongClick = { song ->
                // Play the artist song
                (activity as? MainActivity)?.playMusic(song)
            },
            onFavoriteToggle = { song ->
                // Toggle favorite status
                (activity as? MainActivity)?.toggleFavorite(song)
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
        binding.titleText.text = artistName
        songAdapter.submitList(songs)
        
        if (songs.isNotEmpty()) {
            binding.recyclerView.visibility = View.VISIBLE
            binding.emptyStateText.visibility = View.GONE
        } else {
            binding.recyclerView.visibility = View.GONE
            binding.emptyStateText.visibility = View.VISIBLE
        }
    }
    
    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
