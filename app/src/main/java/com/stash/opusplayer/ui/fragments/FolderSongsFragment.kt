package com.stash.opusplayer.ui.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.stash.opusplayer.data.Song
import com.stash.opusplayer.databinding.FragmentFolderSongsBinding
import com.stash.opusplayer.ui.MainActivity
import com.stash.opusplayer.ui.adapters.SongAdapter
import com.stash.opusplayer.utils.MetadataExtractor
import kotlinx.coroutines.launch

class FolderSongsFragment : Fragment() {
    private var _binding: FragmentFolderSongsBinding? = null
    private val binding get() = _binding!!

    private lateinit var songAdapter: SongAdapter
    private lateinit var metadataExtractor: MetadataExtractor

    private var folderName: String = ""
    private var songs: List<Song> = emptyList()

    companion object {
        private const val ARG_FOLDER_NAME = "folder_name"
        private const val ARG_SONGS = "songs"

        fun newInstance(folderName: String, songs: ArrayList<Song>): FolderSongsFragment {
            val f = FolderSongsFragment()
            f.arguments = Bundle().apply {
                putString(ARG_FOLDER_NAME, folderName)
                putParcelableArrayList(ARG_SONGS, songs)
            }
            return f
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        arguments?.let {
            folderName = it.getString(ARG_FOLDER_NAME, "")
            songs = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                it.getParcelableArrayList(ARG_SONGS, Song::class.java) ?: emptyList()
            } else {
                @Suppress("DEPRECATION")
                it.getParcelableArrayList<Song>(ARG_SONGS) ?: emptyList()
            }
        }
    }

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentFolderSongsBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        metadataExtractor = MetadataExtractor(requireContext())
        setupRecycler()
        loadSongs()
    }

    private fun setupRecycler() {
        songAdapter = SongAdapter(
            onSongClick = { song ->
                val list = songAdapter.currentList
                val index = list.indexOfFirst { it.id == song.id }.let { if (it >= 0) it else 0 }
                (activity as? MainActivity)?.playSongsStartingFrom(list, index, "Folder: ${folderName}")
            },
            onFavoriteToggle = { song -> (activity as? MainActivity)?.toggleFavorite(song) },
            onAddToPlaylist = { song -> (activity as? MainActivity)?.addToPlaylist(song) },
            onPlayNext = { song -> (activity as? MainActivity)?.playNext(song) },
            onAddToQueue = { song -> (activity as? MainActivity)?.addToQueueTail(song) },
            onShowFeedback = { msg -> (activity as? MainActivity)?.showPlayingBanner(msg) },
            metadataExtractor = metadataExtractor,
            lifecycleScope = viewLifecycleOwner.lifecycleScope
        )
        binding.recyclerView.apply {
            adapter = songAdapter
            layoutManager = LinearLayoutManager(requireContext())
        }
    }

    private fun loadSongs() {
        binding.titleText.text = folderName
        songAdapter.submitList(songs)
        if (songs.isNotEmpty()) {
            binding.recyclerView.visibility = View.VISIBLE
            binding.emptyStateText.visibility = View.GONE
        } else {
            binding.recyclerView.visibility = View.GONE
            binding.emptyStateText.text = "No songs found in this folder"
            binding.emptyStateText.visibility = View.VISIBLE
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
