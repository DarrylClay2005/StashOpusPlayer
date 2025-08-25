package com.stash.opusplayer.ui.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.recyclerview.widget.LinearLayoutManager
import com.stash.opusplayer.data.Song
import com.stash.opusplayer.databinding.FragmentArtistSongsBinding
import com.stash.opusplayer.ui.MainActivity
import com.stash.opusplayer.ui.adapters.SongAdapter
import com.stash.opusplayer.utils.MetadataExtractor

class FolderDetailFragment : Fragment() {
    private var _binding: FragmentArtistSongsBinding? = null
    private val binding get() = _binding!!

    private lateinit var songAdapter: SongAdapter
    private lateinit var metadataExtractor: MetadataExtractor

    private var folderTitle: String = ""
    private var songs: List<Song> = emptyList()

    companion object {
        private const val ARG_FOLDER_TITLE = "folder_title"
        private const val ARG_SONGS = "songs"

        fun newInstance(title: String, songs: ArrayList<Song>): FolderDetailFragment {
            val f = FolderDetailFragment()
            val args = Bundle().apply {
                putString(ARG_FOLDER_TITLE, title)
                putParcelableArrayList(ARG_SONGS, songs)
            }
            f.arguments = args
            return f
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        arguments?.let {
            folderTitle = it.getString(ARG_FOLDER_TITLE, "")
            songs = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                it.getParcelableArrayList(ARG_SONGS, Song::class.java) ?: emptyList()
            } else {
                @Suppress("DEPRECATION")
                it.getParcelableArrayList<Song>(ARG_SONGS) ?: emptyList()
            }
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
        setupRecycler()
        bindData()
    }

    private fun setupRecycler() {
        songAdapter = SongAdapter(
            onSongClick = { song -> (activity as? MainActivity)?.playMusic(song) },
            onFavoriteToggle = { song -> (activity as? MainActivity)?.toggleFavorite(song) },
            onAddToPlaylist = { song -> (activity as? MainActivity)?.addToPlaylist(song) },
            metadataExtractor = metadataExtractor
        )
        binding.recyclerView.layoutManager = LinearLayoutManager(requireContext())
        binding.recyclerView.adapter = songAdapter
    }

    private fun bindData() {
        binding.titleText.text = folderTitle
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

