package com.stash.opusplayer.ui.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.appcompat.app.AlertDialog
import com.stash.opusplayer.R
import com.stash.opusplayer.databinding.FragmentMusicLibraryBinding
import com.stash.opusplayer.data.MusicRepository
import com.stash.opusplayer.data.Song
import com.stash.opusplayer.ui.MainActivity
import com.stash.opusplayer.ui.adapters.SongAdapter
import com.stash.opusplayer.ui.appearance.ThemeManager
import kotlinx.coroutines.*

class MusicLibraryFragment : Fragment() {
    
    private var currentColumns: Int = 1
    private var gridDecoration: RecyclerView.ItemDecoration? = null
    
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
        // Resolve initial columns from prefs
        val prefs = requireContext().getSharedPreferences("settings", 0)
        currentColumns = com.stash.opusplayer.utils.PrefsUtils.resolveColumnsForScreen(
            prefs,
            com.stash.opusplayer.utils.PrefsKeys.SONGS_VIEW_COLUMNS,
            com.stash.opusplayer.utils.PrefsKeys.DEFAULT_SONGS_VIEW_COLUMNS,
            1
        )
        setupRecyclerView()
        setupLayoutToggle()
        setupSearchButton()
        setupSortButton()
        setupLikedButton()
        applyAdaptiveChrome()
        loadSongs()
    }
    
    private fun setupRecyclerView() {
val metadataExtractor = com.stash.opusplayer.utils.MetadataExtractor(requireContext())
        
        songAdapter = SongAdapter(
            onSongClick = { song ->
                val list = songAdapter.currentList
                val index = list.indexOfFirst { it.id == song.id }.let { if (it >= 0) it else 0 }
                (activity as? MainActivity)?.playSongsStartingFrom(list, index, "Songs")
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
                // Add to playlist
                (activity as? MainActivity)?.addToPlaylist(song)
            },
            onPlayNext = { song -> (activity as? MainActivity)?.playNext(song) },
            onAddToQueue = { song -> (activity as? MainActivity)?.addToQueueTail(song) },
            onShowFeedback = { message -> (activity as? MainActivity)?.showPlayingBanner(message) },
            metadataExtractor = metadataExtractor
        )
        
        binding.recyclerView.adapter = songAdapter
        binding.recyclerView.clipToPadding = false
        applyColumns(currentColumns)
    }

    private fun applyAdaptiveChrome() {
        val context = requireContext()
        val outerPadding = ThemeManager.scaleDp(context, 10)
        val compactButtonWidth = ThemeManager.scaleDp(context, 40)
        val compactButtonHeight = ThemeManager.scaleDp(context, 34)
        val compactIconSize = ThemeManager.scaleDp(context, 16)
        val scanHorizontalPadding = ThemeManager.scaleDp(context, 10)
        val recyclerBottomPadding = ThemeManager.scaleDp(context, 22)

        binding.root.setPadding(outerPadding, outerPadding, outerPadding, outerPadding)
        binding.libraryHeaderTitle.textSize = ThemeManager.scaleSp(context, 16f)
        binding.libraryHeaderIcon.layoutParams = binding.libraryHeaderIcon.layoutParams.apply {
            width = ThemeManager.scaleDp(context, 24)
            height = ThemeManager.scaleDp(context, 24)
        }
        binding.libraryHeader.layoutParams = (binding.libraryHeader.layoutParams as? ViewGroup.MarginLayoutParams)?.apply {
            bottomMargin = ThemeManager.scaleDp(context, 10)
        } ?: binding.libraryHeader.layoutParams

        listOf(binding.likedButton, binding.searchButton, binding.sortButton, binding.layoutButton).forEach { button ->
            button.layoutParams = button.layoutParams.apply {
                width = compactButtonWidth
                height = compactButtonHeight
            }
            button.minimumWidth = compactButtonWidth
            button.minimumHeight = compactButtonHeight
            button.iconSize = compactIconSize
            button.insetTop = 0
            button.insetBottom = 0
        }

        binding.scanButton.layoutParams = binding.scanButton.layoutParams.apply {
            height = compactButtonHeight
        }
        binding.scanButton.minimumHeight = compactButtonHeight
        binding.scanButton.iconSize = ThemeManager.scaleDp(context, 12)
        binding.scanButton.textSize = ThemeManager.scaleSp(context, 10.5f)
        binding.scanButton.insetTop = 0
        binding.scanButton.insetBottom = 0
        binding.scanButton.setPadding(scanHorizontalPadding, 0, scanHorizontalPadding, 0)

        binding.recyclerView.setPadding(0, ThemeManager.scaleDp(context, 2), 0, recyclerBottomPadding)
        binding.emptyStateText.textSize = ThemeManager.scaleSp(context, 15f)
        binding.emptyStateSubtitle.textSize = ThemeManager.scaleSp(context, 11f)
    }

    private fun setupLayoutToggle() {
        // Set initial icon
        updateLayoutButtonIcon()

        // Short tap cycles among 1→2→3→1
        binding.layoutButton.setOnClickListener { view ->
            val lm = binding.recyclerView.layoutManager
            val firstPos = when (lm) {
                is LinearLayoutManager -> lm.findFirstVisibleItemPosition()
                is GridLayoutManager -> lm.findFirstVisibleItemPosition()
                else -> 0
            }
            currentColumns = when (currentColumns) {
                1 -> 2
                2 -> 3
                else -> 1
            }
            // Persist per-screen override
            val prefs = requireContext().getSharedPreferences("settings", 0)
            prefs.edit().putInt(com.stash.opusplayer.utils.PrefsKeys.SONGS_VIEW_COLUMNS, currentColumns).apply()

            applyColumns(currentColumns)
            updateLayoutButtonIcon()
            // Restore position
            try { binding.recyclerView.scrollToPosition(firstPos) } catch (_: Exception) {}
        }

        // Long-press opens chooser
        binding.layoutButton.setOnLongClickListener { v ->
            try { v.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS) } catch (_: Exception) {}
            val choices = arrayOf(
                getString(com.stash.opusplayer.R.string.layout_list),
                getString(com.stash.opusplayer.R.string.layout_two_columns),
                getString(com.stash.opusplayer.R.string.layout_three_columns)
            )
            val selectedIndex = when (currentColumns) { 1 -> 0; 2 -> 1; else -> 2 }
            androidx.appcompat.app.AlertDialog.Builder(requireContext())
                .setTitle(com.stash.opusplayer.R.string.choose_layout_title)
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
                        prefs.edit().putInt(com.stash.opusplayer.utils.PrefsKeys.SONGS_VIEW_COLUMNS, currentColumns).apply()
                        applyColumns(currentColumns)
                        updateLayoutButtonIcon()
                        try { binding.recyclerView.scrollToPosition(firstPos) } catch (_: Exception) {}
                    }
                    dialog.dismiss()
                }
                .setNegativeButton(com.stash.opusplayer.R.string.cancel, null)
                .show()
            true
        }
    }

    private fun updateLayoutButtonIcon() {
        val iconRes = if (currentColumns == 1) com.stash.opusplayer.R.drawable.ic_view_list else com.stash.opusplayer.R.drawable.ic_view_grid
        try { binding.layoutButton.setIconResource(iconRes) } catch (_: Exception) {}
    }

    private fun applyColumns(cols: Int) {
        // Remove previous decoration if any
        gridDecoration?.let { binding.recyclerView.removeItemDecoration(it) }
        if (cols == 1) {
            binding.recyclerView.layoutManager = LinearLayoutManager(requireContext())
            songAdapter.setColumns(1)
            gridDecoration = null
        } else {
            binding.recyclerView.layoutManager = GridLayoutManager(requireContext(), cols)
            songAdapter.setColumns(cols)
            val spacing = ThemeManager.scaleDp(requireContext(), 8)
            gridDecoration = com.stash.opusplayer.ui.widgets.GridSpacingItemDecoration(cols, spacing, true)
            binding.recyclerView.addItemDecoration(gridDecoration!!)
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
    
    private fun setupSortButton() {
        binding.sortButton.setOnClickListener {
            showSortDialog()
        }
    }
    
    private fun setupLikedButton() {
        binding.likedButton.setOnClickListener { view ->
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
                
            // Show visual feedback via parent activity
            (activity as? MainActivity)?.showPlayingBanner("Loading liked songs...")
            
            // Navigate to Liked Songs fragment
            (activity as? MainActivity)?.let { mainActivity ->
val favoritesFragment = com.stash.opusplayer.ui.fragments.FavoritesFragment()
                mainActivity.supportFragmentManager.beginTransaction()
.replace(com.stash.opusplayer.R.id.main_content, favoritesFragment)
                    .addToBackStack(null)
                    .commit()
                mainActivity.supportActionBar?.title = "Liked Songs"
            }
        }
    }
    
    private fun showSearchDialog() {
        val searchView = EditText(requireContext()).apply {
            hint = "Search songs..."
            val horizontalPadding = ThemeManager.scaleDp(requireContext(), 16)
            val verticalPadding = ThemeManager.scaleDp(requireContext(), 10)
            setPadding(horizontalPadding, verticalPadding, horizontalPadding, verticalPadding)
            textSize = ThemeManager.scaleSp(requireContext(), 14f)
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
        // Show loading state temporarily for better UX
        binding.emptyStateText.text = "Searching..."
        binding.emptyStateContainer.visibility = View.VISIBLE
        binding.recyclerView.visibility = View.GONE
        
        viewLifecycleOwner.lifecycleScope.launch {
            // Add small delay to show search feedback
            kotlinx.coroutines.delay(300)
            
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
                
                // Show visual feedback via parent activity
                (activity as? MainActivity)?.showPlayingBanner("No results for \"$query\". Try different keywords.")
            } else {
                binding.recyclerView.visibility = View.VISIBLE
                binding.emptyStateContainer.visibility = View.GONE
                
                // Show results count via parent activity
                (activity as? MainActivity)?.showPlayingBanner("Found ${filteredSongs.size} song${if (filteredSongs.size != 1) "s" else ""}")
            }
        }
    }
    
    private fun showSortDialog() {
        val sortOptions = arrayOf(
            getString(R.string.sort_by_title),
            getString(R.string.sort_by_artist),
            getString(R.string.sort_by_album),
            getString(R.string.sort_by_duration)
        )
        
        AlertDialog.Builder(requireContext())
            .setTitle(getString(R.string.choose_sort_title))
            .setItems(sortOptions) { _, which ->
                val sorted = when (which) {
                    0 -> allSongs.sortedBy { it.title.lowercase() }
                    1 -> allSongs.sortedBy { it.artist.lowercase() }
                    2 -> allSongs.sortedBy { it.album.lowercase() }
                    3 -> allSongs.sortedBy { it.duration }
                    else -> allSongs
                }
                songAdapter.submitList(sorted)
                (activity as? MainActivity)?.showPlayingBanner("Sorted by ${sortOptions[which]}")
            }
            .setNegativeButton(getString(R.string.cancel), null)
            .show()
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
(activity as? com.stash.opusplayer.ui.MainActivity)?.notifyContentLoaded()
            } catch (e: Exception) {
                val b = _binding ?: return@launch
                b.recyclerView.visibility = View.GONE
                b.emptyStateText.visibility = View.VISIBLE
(activity as? com.stash.opusplayer.ui.MainActivity)?.notifyContentLoaded()
            }
        }
    }
    
    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
