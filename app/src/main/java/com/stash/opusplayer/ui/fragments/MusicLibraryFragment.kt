package com.stash.opusplayer.ui.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import androidx.appcompat.app.AlertDialog
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.stash.opusplayer.R
import com.stash.opusplayer.data.MusicRepository
import com.stash.opusplayer.data.Song
import com.stash.opusplayer.databinding.FragmentMusicLibraryBinding
import com.stash.opusplayer.ui.MainActivity
import com.stash.opusplayer.ui.adapters.SongAdapter
import com.stash.opusplayer.ui.appearance.ThemeManager
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class MusicLibraryFragment : Fragment() {

    private var currentColumns: Int = 1
    private var gridDecoration: RecyclerView.ItemDecoration? = null
    private var loadSongsJob: Job? = null

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
        setupScanButton()
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
                (activity as? MainActivity)?.toggleFavorite(song)
                viewLifecycleOwner.lifecycleScope.launch {
                    delay(450)
                    loadSongs()
                }
            },
            onAddToPlaylist = { song ->
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
        val compactButtonWidth = ThemeManager.scaleDp(context, 42)
        val compactButtonHeight = ThemeManager.scaleDp(context, 36)
        val compactIconSize = ThemeManager.scaleDp(context, 16)
        val scanHorizontalPadding = ThemeManager.scaleDp(context, 10)
        val recyclerBottomPadding = ThemeManager.scaleDp(context, 24)

        binding.root.setPadding(outerPadding, outerPadding, outerPadding, outerPadding)
        binding.libraryHeaderTitle.textSize = ThemeManager.scaleSp(context, 18f)
        binding.libraryHeaderSubtitle.textSize = ThemeManager.scaleSp(context, 11.5f)
        binding.libraryStatsText.textSize = ThemeManager.scaleSp(context, 10.5f)
        binding.libraryHeaderIcon.layoutParams = binding.libraryHeaderIcon.layoutParams.apply {
            width = ThemeManager.scaleDp(context, 24)
            height = ThemeManager.scaleDp(context, 24)
        }

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
        binding.emptyStateSubtitle.textSize = ThemeManager.scaleSp(context, 11.5f)
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
            currentColumns = when (currentColumns) {
                1 -> 2
                2 -> 3
                else -> 1
            }
            val prefs = requireContext().getSharedPreferences("settings", 0)
            prefs.edit().putInt(com.stash.opusplayer.utils.PrefsKeys.SONGS_VIEW_COLUMNS, currentColumns).apply()

            applyColumns(currentColumns)
            updateLayoutButtonIcon()
            try {
                binding.recyclerView.scrollToPosition(firstPos)
            } catch (_: Exception) {
            }
        }

        binding.layoutButton.setOnLongClickListener { view ->
            try {
                view.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
            } catch (_: Exception) {
            }
            val choices = arrayOf(
                getString(R.string.layout_list),
                getString(R.string.layout_two_columns),
                getString(R.string.layout_three_columns)
            )
            val selectedIndex = when (currentColumns) {
                1 -> 0
                2 -> 1
                else -> 2
            }
            AlertDialog.Builder(requireContext())
                .setTitle(R.string.choose_layout_title)
                .setSingleChoiceItems(choices, selectedIndex) { dialog, which ->
                    val newCols = when (which) {
                        0 -> 1
                        1 -> 2
                        else -> 3
                    }
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
                        try {
                            binding.recyclerView.scrollToPosition(firstPos)
                        } catch (_: Exception) {
                        }
                    }
                    dialog.dismiss()
                }
                .setNegativeButton(R.string.cancel, null)
                .show()
            true
        }
    }

    private fun updateLayoutButtonIcon() {
        val iconRes = if (currentColumns == 1) R.drawable.ic_view_list else R.drawable.ic_view_grid
        try {
            binding.layoutButton.setIconResource(iconRes)
        } catch (_: Exception) {
        }
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
            val spacing = ThemeManager.scaleDp(requireContext(), 8)
            gridDecoration = com.stash.opusplayer.ui.widgets.GridSpacingItemDecoration(cols, spacing, true)
            binding.recyclerView.addItemDecoration(gridDecoration!!)
        }
    }

    private fun setupSearchButton() {
        binding.searchButton.setOnClickListener { view ->
            animateHeaderButton(view)
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
            animateHeaderButton(view)
            (activity as? MainActivity)?.showPlayingBanner("Loading liked songs...")
            (activity as? MainActivity)?.let { mainActivity ->
                val favoritesFragment = FavoritesFragment()
                mainActivity.supportFragmentManager.beginTransaction()
                    .replace(R.id.main_content, favoritesFragment)
                    .addToBackStack(null)
                    .commit()
                mainActivity.supportActionBar?.title = "Liked Songs"
            }
        }
    }

    private fun setupScanButton() {
        binding.scanButton.setOnClickListener { view ->
            animateHeaderButton(view)
            refreshLibrary()
        }
    }

    private fun animateHeaderButton(view: View) {
        view.animate()
            .scaleX(0.92f)
            .scaleY(0.92f)
            .setDuration(100)
            .withEndAction {
                view.animate()
                    .scaleX(1f)
                    .scaleY(1f)
                    .setDuration(100)
                    .start()
            }
            .start()
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
                    songAdapter.submitList(allSongs)
                    binding.recyclerView.visibility = if (allSongs.isEmpty()) View.GONE else View.VISIBLE
                    binding.emptyStateContainer.visibility = if (allSongs.isEmpty()) View.VISIBLE else View.GONE
                    updateLibraryHeader(
                        headline = "Song Library",
                        subtitle = "Recent tracks, deep cuts, and loose files in one place.",
                        showingCount = allSongs.size,
                        totalCount = allSongs.size
                    )
                }
            }
            .setNegativeButton("Show All") { _, _ ->
                songAdapter.submitList(allSongs)
                binding.recyclerView.visibility = if (allSongs.isEmpty()) View.GONE else View.VISIBLE
                binding.emptyStateContainer.visibility = if (allSongs.isEmpty()) View.VISIBLE else View.GONE
                updateLibraryHeader(
                    headline = "Song Library",
                    subtitle = "Recent tracks, deep cuts, and loose files in one place.",
                    showingCount = allSongs.size,
                    totalCount = allSongs.size
                )
            }
            .setNeutralButton("Cancel", null)
            .show()

        searchView.requestFocus()
    }

    private fun searchSongs(query: String) {
        binding.emptyStateText.text = "Searching..."
        binding.emptyStateSubtitle.text = "Matching titles, artists, and albums in your library."
        binding.emptyStateContainer.visibility = View.VISIBLE
        binding.recyclerView.visibility = View.GONE

        viewLifecycleOwner.lifecycleScope.launch {
            delay(220)

            val filteredSongs = allSongs.filter { song ->
                song.title.contains(query, ignoreCase = true) ||
                    song.artist.contains(query, ignoreCase = true) ||
                    song.album.contains(query, ignoreCase = true)
            }

            songAdapter.submitList(filteredSongs)

            if (filteredSongs.isEmpty()) {
                binding.recyclerView.visibility = View.GONE
                binding.emptyStateText.text = "No songs found for \"$query\""
                binding.emptyStateSubtitle.text = "Try a different artist, title, album, or run a library refresh."
                binding.emptyStateContainer.visibility = View.VISIBLE
                updateLibraryHeader(
                    headline = "No search matches",
                    subtitle = "The library is loaded, but this search did not match any local tracks.",
                    showingCount = 0,
                    totalCount = allSongs.size
                )
                (activity as? MainActivity)?.showPlayingBanner("No results for \"$query\". Try different keywords.")
            } else {
                binding.recyclerView.visibility = View.VISIBLE
                binding.emptyStateContainer.visibility = View.GONE
                updateLibraryHeader(
                    headline = "Search Results",
                    subtitle = "Showing the closest matches from your local library.",
                    showingCount = filteredSongs.size,
                    totalCount = allSongs.size
                )
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
                updateLibraryHeader(
                    headline = "Song Library",
                    subtitle = "Sorted by ${sortOptions[which]}.",
                    showingCount = sorted.size,
                    totalCount = allSongs.size
                )
                (activity as? MainActivity)?.showPlayingBanner("Sorted by ${sortOptions[which]}")
            }
            .setNegativeButton(getString(R.string.cancel), null)
            .show()
    }

    private fun loadSongs() {
        loadSongsJob?.cancel()
        loadSongsJob = viewLifecycleOwner.lifecycleScope.launch {
            try {
                val fast = musicRepository.getAllSongsFromAllSourcesFast()
                val currentBinding = _binding ?: return@launch
                if (fast.isNotEmpty()) {
                    allSongs = fast
                    songAdapter.submitList(fast)
                    currentBinding.recyclerView.visibility = View.VISIBLE
                    currentBinding.emptyStateContainer.visibility = View.GONE
                    updateLibraryHeader(
                        headline = "Song Library",
                        subtitle = "Recent tracks, deep cuts, and loose files in one place.",
                        showingCount = fast.size,
                        totalCount = fast.size
                    )
                } else {
                    currentBinding.recyclerView.visibility = View.GONE
                    currentBinding.emptyStateText.text = "No music found"
                    currentBinding.emptyStateSubtitle.text = "Scan your device, add folders, or download tracks to bring the library back."
                    currentBinding.emptyStateContainer.visibility = View.VISIBLE
                    updateLibraryHeader(
                        headline = "Library Empty",
                        subtitle = "Nothing playable showed up yet, so the library is ready for a fresh scan.",
                        showingCount = 0,
                        totalCount = 0
                    )
                }

                launch {
                    val full = musicRepository.getAllSongsFromAllSources()
                    if (_binding != null && full.isNotEmpty()) {
                        allSongs = full
                        songAdapter.submitList(full)
                        updateLibraryHeader(
                            headline = "Song Library",
                            subtitle = "Recent tracks, deep cuts, and loose files in one place.",
                            showingCount = full.size,
                            totalCount = full.size
                        )
                    }
                }

                (activity as? MainActivity)?.notifyContentLoaded()
            } catch (_: Exception) {
                val currentBinding = _binding ?: return@launch
                currentBinding.recyclerView.visibility = View.GONE
                currentBinding.emptyStateText.visibility = View.VISIBLE
                currentBinding.emptyStateText.text = "Library unavailable"
                currentBinding.emptyStateSubtitle.text = "The library hit a read error. Try rescanning after storage access is available."
                currentBinding.emptyStateContainer.visibility = View.VISIBLE
                updateLibraryHeader(
                    headline = "Library unavailable",
                    subtitle = "A scan problem interrupted loading. Refreshing the library should recover it.",
                    showingCount = 0,
                    totalCount = allSongs.size
                )
                (activity as? MainActivity)?.notifyContentLoaded()
            }
        }
    }

    private fun refreshLibrary() {
        binding.scanButton.isEnabled = false
        binding.scanButton.text = "Refreshing"
        updateLibraryHeader(
            headline = "Refreshing Library",
            subtitle = "Scanning local sources and rebuilding the track list.",
            showingCount = allSongs.size,
            totalCount = allSongs.size
        )
        binding.emptyStateText.text = "Refreshing music library..."
        binding.emptyStateSubtitle.text = "Scanning device storage, folders, and linked sources."
        if (allSongs.isEmpty()) {
            binding.emptyStateContainer.visibility = View.VISIBLE
            binding.recyclerView.visibility = View.GONE
        }

        viewLifecycleOwner.lifecycleScope.launch {
            runCatching {
                com.stash.opusplayer.work.MetadataScanWorker.scheduleMetadataScan(requireContext(), forceRescan = true)
            }
            delay(250)
            loadSongs()
            binding.scanButton.isEnabled = true
            binding.scanButton.text = "Rescan"
            (activity as? MainActivity)?.showPlayingBanner("Library refresh started")
        }
    }

    private fun updateLibraryHeader(
        headline: String,
        subtitle: String,
        showingCount: Int,
        totalCount: Int
    ) {
        if (_binding == null) return
        binding.libraryHeaderTitle.text = headline
        binding.libraryHeaderSubtitle.text = subtitle
        binding.libraryStatsText.text = when {
            totalCount <= 0 -> "No tracks ready"
            showingCount == totalCount -> "$totalCount tracks ready"
            else -> "$showingCount of $totalCount tracks showing"
        }
    }

    override fun onDestroyView() {
        loadSongsJob?.cancel()
        super.onDestroyView()
        _binding = null
    }
}
