package com.stash.stashwave.ui.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.stash.stashwave.data.MusicRepository
import com.stash.stashwave.databinding.FragmentFoldersBinding
import com.stash.stashwave.ui.adapters.FolderAdapter
import kotlinx.coroutines.launch
import java.io.File
import android.net.Uri

class FoldersFragment : Fragment() {

    private var currentColumns: Int = 1
    private var gridDecoration: RecyclerView.ItemDecoration? = null

    private var _binding: FragmentFoldersBinding? = null
    private val binding get() = _binding!!

    private lateinit var adapter: FolderAdapter
    private lateinit var repository: MusicRepository

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentFoldersBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        repository = MusicRepository(requireContext())
        // Resolve initial columns from prefs
        val prefs = requireContext().getSharedPreferences("settings", 0)
        currentColumns = com.stash.stashwave.utils.PrefsUtils.resolveColumnsForScreen(
            prefs,
            com.stash.stashwave.utils.PrefsKeys.FOLDERS_VIEW_COLUMNS,
            com.stash.stashwave.utils.PrefsKeys.DEFAULT_FOLDERS_VIEW_COLUMNS,
            1
        )
        setupRecyclerView()
        setupLayoutToggle()
        setupRefresh()
        loadFolders()
    }

    private fun setupRecyclerView() {
        adapter = FolderAdapter { info ->
            val fragment = FolderDetailFragment.newInstance(info.path, ArrayList(info.songs))
            parentFragmentManager.beginTransaction()
                .replace(com.stash.stashwave.R.id.main_content, fragment)
                .addToBackStack(null)
                .commit()
        }.also {
            it.setColumns(currentColumns)
        }
        binding.recyclerView.adapter = this@FoldersFragment.adapter
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
            prefs.edit().putInt(com.stash.stashwave.utils.PrefsKeys.FOLDERS_VIEW_COLUMNS, currentColumns).apply()
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
                        val lm2 = binding.recyclerView.layoutManager
                        val firstPos2 = when (lm2) {
                            is LinearLayoutManager -> lm2.findFirstVisibleItemPosition()
                            is GridLayoutManager -> lm2.findFirstVisibleItemPosition()
                            else -> 0
                        }
                        currentColumns = newCols
                        val prefs = requireContext().getSharedPreferences("settings", 0)
                        prefs.edit().putInt(com.stash.stashwave.utils.PrefsKeys.FOLDERS_VIEW_COLUMNS, currentColumns).apply()
                        applyColumns(currentColumns)
                        updateLayoutButtonIcon()
                        try { binding.recyclerView.scrollToPosition(firstPos2) } catch (_: Exception) {}
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
            adapter.setColumns(1)
        } else {
            binding.recyclerView.layoutManager = GridLayoutManager(requireContext(), cols)
            adapter.setColumns(cols)
            val spacing = resources.getDimensionPixelSize(com.stash.stashwave.R.dimen.grid_spacing)
            gridDecoration = com.stash.stashwave.ui.widgets.GridSpacingItemDecoration(cols, spacing, true)
            binding.recyclerView.addItemDecoration(gridDecoration!!)
        }
    }

    private fun setupRefresh() {
        binding.swipeRefresh.setOnRefreshListener {
            loadFolders()
        }
    }

    private fun loadFolders() {
        viewLifecycleOwner.lifecycleScope.launch {
            try {
                val songs = repository.getAllSongsFromAllSourcesFast()
                val folders = songs
                    .groupBy { song ->
                        if (song.path.startsWith("content://")) {
                            // Use relativePath set during SAF scan; fallback to content URI host
                            val rp = song.relativePath.ifBlank { "Content/${Uri.parse(song.path).host ?: "Music"}/" }
                            // Normalize leading/trailing slashes
                            rp.trimStart('/').trimEnd('/')
                        } else {
                            File(song.path).parent ?: "/"
                        }
                    }
                    .map { (path, group) -> FolderInfo(path, group.size, group) }
                    .sortedBy { it.path.lowercase() }
                val b = _binding ?: return@launch
                if (folders.isNotEmpty()) {
                    adapter.submitList(folders)
b.recyclerView.visibility = View.VISIBLE
                    b.emptyStateText.visibility = View.GONE
                    b.swipeRefresh.isRefreshing = false
                } else {
b.recyclerView.visibility = View.GONE
                    b.emptyStateText.visibility = View.VISIBLE
                    b.swipeRefresh.isRefreshing = false
                }
            } catch (_: Exception) {
                val b = _binding ?: return@launch
b.recyclerView.visibility = View.GONE
                b.emptyStateText.visibility = View.VISIBLE
                b.swipeRefresh.isRefreshing = false
            }
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}

data class FolderInfo(
    val path: String,
    val songCount: Int,
    val songs: List<com.stash.stashwave.data.Song>
)
