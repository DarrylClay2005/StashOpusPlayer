package com.stash.opusplayer.ui.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.stash.opusplayer.data.MusicRepository
import com.stash.opusplayer.data.Song
import com.stash.opusplayer.databinding.FragmentPlaylistDetailBinding
import com.stash.opusplayer.ui.MainActivity
import com.stash.opusplayer.ui.adapters.SongAdapter
import com.stash.opusplayer.utils.MetadataExtractor
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class PlaylistDetailFragment : Fragment() {

    private var _binding: FragmentPlaylistDetailBinding? = null
    private val binding get() = _binding!!

    private lateinit var repository: MusicRepository
    private lateinit var adapter: SongAdapter
    private lateinit var metadataExtractor: MetadataExtractor

    private var playlistId: Long = 0

    companion object {
        private const val ARG_ID = "playlist_id"
        fun newInstance(playlistId: Long): PlaylistDetailFragment {
            return PlaylistDetailFragment().apply {
                arguments = Bundle().apply { putLong(ARG_ID, playlistId) }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        playlistId = arguments?.getLong(ARG_ID) ?: 0
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentPlaylistDetailBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        repository = MusicRepository(requireContext())
        metadataExtractor = MetadataExtractor(requireContext())
        setupRecycler()
        observeTracks()
    }

    private fun setupRecycler() {
        adapter = SongAdapter(
            onSongClick = { song -> (activity as? MainActivity)?.playMusic(song) },
            onFavoriteToggle = { song -> (activity as? MainActivity)?.toggleFavorite(song) },
            onAddToPlaylist = { _ -> },
            metadataExtractor = metadataExtractor
        )
        binding.recyclerView.layoutManager = LinearLayoutManager(requireContext())
        binding.recyclerView.adapter = adapter
    }

    private fun observeTracks() {
        viewLifecycleOwner.lifecycleScope.launch {
            repository.getPlaylistTracks(playlistId).collectLatest { tracks ->
                val b = _binding ?: return@collectLatest
                val songs = tracks.map { t ->
                    Song(
                        id = t.songId,
                        title = t.title,
                        artist = t.artist,
                        album = t.album,
                        duration = t.duration,
                        path = t.path
                    )
                }
                if (songs.isNotEmpty()) {
                    adapter.submitList(songs)
                    b.recyclerView.visibility = View.VISIBLE
                    b.emptyStateText.visibility = View.GONE
                } else {
                    b.recyclerView.visibility = View.GONE
                    b.emptyStateText.visibility = View.VISIBLE
                }
            }
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}

