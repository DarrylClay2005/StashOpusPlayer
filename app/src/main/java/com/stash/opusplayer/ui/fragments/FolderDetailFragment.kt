package com.stash.stashwave.ui.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.stash.stashwave.data.Song
import com.stash.stashwave.databinding.FragmentArtistSongsBinding
import com.stash.stashwave.ui.MainActivity
import com.stash.stashwave.ui.adapters.SongAdapter
import com.stash.stashwave.utils.MetadataExtractor

class FolderDetailFragment : Fragment() {
    private var currentColumns: Int = 1
    private var gridDecoration: RecyclerView.ItemDecoration? = null
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
        // Resolve initial columns from prefs
        val prefs = requireContext().getSharedPreferences("settings", 0)
        currentColumns = com.stash.stashwave.utils.PrefsUtils.resolveColumnsForScreen(
            prefs,
            com.stash.stashwave.utils.PrefsKeys.FOLDER_DETAIL_VIEW_COLUMNS,
            com.stash.stashwave.utils.PrefsKeys.DEFAULT_FOLDER_DETAIL_VIEW_COLUMNS,
            1
        )
        setupRecycler()
        setupLayoutToggle()
        bindData()
    }

    private fun setupRecycler() {
        songAdapter = SongAdapter(
            onSongClick = { song ->
                val list = songAdapter.currentList
                val index = list.indexOfFirst { it.id == song.id }.let { if (it >= 0) it else 0 }
                (activity as? MainActivity)?.playSongsStartingFrom(list, index, "Folder: ${folderTitle}")
            },
            onFavoriteToggle = { song -> (activity as? MainActivity)?.toggleFavorite(song) },
            onAddToPlaylist = { song -> (activity as? MainActivity)?.addToPlaylist(song) },
            onPlayNext = { song -> (activity as? MainActivity)?.playNext(song) },
            onAddToQueue = { song -> (activity as? MainActivity)?.addToQueueTail(song) },
            metadataExtractor = metadataExtractor
        )
        binding.recyclerView.adapter = songAdapter
        applyColumns(currentColumns)
    }

    private fun setupLayoutToggle() {
        updateLayoutButtonIcon()
        binding.layoutButton.setOnClickListener {
            val lm = binding.recyclerView.layoutManager
            val firstPos = when (lm) {
                is LinearLayoutManager -> lm.findFirstVisibleItemPosition()
                is GridLayoutManager -> lm.findFirstVisibleItemPosition()
                else -> 0
            }
            currentColumns = when (currentColumns) { 1 -> 2; 2 -> 3; else -> 1 }
            val prefs = requireContext().getSharedPreferences("settings", 0)
            prefs.edit().putInt(com.stash.stashwave.utils.PrefsKeys.FOLDER_DETAIL_VIEW_COLUMNS, currentColumns).apply()
            applyColumns(currentColumns)
            updateLayoutButtonIcon()
            try { binding.recyclerView.scrollToPosition(firstPos) } catch (_: Exception) {}
        }
        binding.layoutButton.setOnLongClickListener { v ->
            try { v.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS) } catch (_: Exception) {}
            val choices = arrayOf(
                getString(com.stash.stashwave.R.string.layout_list),
                getString(com.stash.stashwave.R.string.layout_two_columns),
                getString(com.stash.stashwave.R.string.layout_three_columns)
            )
            val selectedIndex = when (currentColumns) { 1 -> 0; 2 -> 1; else -> 2 }
            androidx.appcompat.app.AlertDialog.Builder(requireContext())
                .setTitle(com.stash.stashwave.R.string.choose_layout_title)
                .setSingleChoiceItems(choices, selectedIndex) { dialog, which ->
                    val newCols = when (which) { 0 -> 1; 1 -> 2; else -> 3 }
                    if (newCols != currentColumns) {
                        val lm = binding.recyclerView.layoutManager
                        val firstPos = when (lm) {
                            is LinearLayoutManager -> lm.findFirstVisibleItemPosition()
                            is GridLayoutManager -> lm.findFirstVisibleItemPosition()
                            else -> 0
                        }
                        currentColumns = newCols
                        val prefs = requireContext().getSharedPreferences("settings", 0)
                        prefs.edit().putInt(com.stash.stashwave.utils.PrefsKeys.FOLDER_DETAIL_VIEW_COLUMNS, currentColumns).apply()
                        applyColumns(currentColumns)
                        updateLayoutButtonIcon()
                        try { binding.recyclerView.scrollToPosition(firstPos) } catch (_: Exception) {}
                    }
                    dialog.dismiss()
                }
                .setNegativeButton(com.stash.stashwave.R.string.cancel, null)
                .show()
            true
        }
    }

    private fun updateLayoutButtonIcon() {
        val iconRes = if (currentColumns == 1) com.stash.stashwave.R.drawable.ic_view_list else com.stash.stashwave.R.drawable.ic_view_grid
        try { binding.layoutButton.setIconResource(iconRes) } catch (_: Exception) {}
    }

    private fun applyColumns(cols: Int) {
        gridDecoration?.let { binding.recyclerView.removeItemDecoration(it) }
        if (cols == 1) {
            binding.recyclerView.layoutManager = LinearLayoutManager(requireContext())
            songAdapter.setColumns(1)
            gridDecoration = null
        } else {
            binding.recyclerView.layoutManager = GridLayoutManager(requireContext(), cols)
            songAdapter.setColumns(cols)
            val spacing = resources.getDimensionPixelSize(com.stash.stashwave.R.dimen.grid_spacing)
            gridDecoration = com.stash.stashwave.ui.widgets.GridSpacingItemDecoration(cols, spacing, true)
            binding.recyclerView.addItemDecoration(gridDecoration!!)
        }
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

