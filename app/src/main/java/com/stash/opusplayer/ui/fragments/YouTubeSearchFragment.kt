package com.stash.opusplayer.ui.fragments

import android.content.Intent
import android.os.Bundle
import android.view.KeyEvent
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.widget.Toast
import androidx.core.widget.addTextChangedListener
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.stash.opusplayer.data.YouTubeVideo
import com.stash.opusplayer.databinding.FragmentYoutubeSearchBinding
import com.stash.opusplayer.integration.SealIntegration
import com.stash.opusplayer.network.YouTubeApiService
import com.stash.opusplayer.ui.YouTubeStreamingActivity
import com.stash.opusplayer.ui.adapters.YouTubeVideoAdapter
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

class YouTubeSearchFragment : Fragment() {

    private var _binding: FragmentYoutubeSearchBinding? = null
    private val binding get() = _binding!!

    private lateinit var youTubeApiService: YouTubeApiService
    private lateinit var videoAdapter: YouTubeVideoAdapter
    private lateinit var linearLayoutManager: LinearLayoutManager

    private val allVideos = mutableListOf<YouTubeVideo>()
    private var currentQuery: String? = null
    private var nextPageToken: String? = null
    private var searchJob: Job? = null
    private var loadMoreJob: Job? = null
    private var isLoadingMore: Boolean = false

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentYoutubeSearchBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        youTubeApiService = YouTubeApiService(requireContext())
        setupRecyclerView()
        setupSearchInput()
        setupDownloadRoutingUi()
        showEmptyState(
            title = "Search YouTube videos",
            subtitle = "Enter a song, artist, or mix to preview it here and hand the download off to Seal."
        )
    }

    private fun setupDownloadRoutingUi() {
        // Downloads are delegated to Seal now, so the old in-app location card was dead UI.
        binding.downloadInfoCard.visibility = View.GONE

        val sealInstalled = SealIntegration.isInstalled(requireContext())
        binding.sealInfoBanner.visibility = View.VISIBLE
        if (sealInstalled) {
            binding.sealInfoText.text =
                "Downloads open in Seal. Search here, preview in-app, then tap Download to continue there."
            binding.sealActionButton.visibility = View.GONE
        } else {
            binding.sealInfoText.text =
                "Install Seal to enable downloads. Playback previews still work inside the app."
            binding.sealActionButton.visibility = View.VISIBLE
            binding.sealActionButton.text = "Install Seal"
            binding.sealActionButton.setOnClickListener {
                SealIntegration.promptInstall(requireContext())
            }
        }
    }

    private fun setupRecyclerView() {
        videoAdapter = YouTubeVideoAdapter(
            onVideoClick = ::openVideoPreview,
            onDownloadClick = ::handleDownloadClick,
            onPreviewClick = ::openVideoPreview
        )

        linearLayoutManager = LinearLayoutManager(requireContext())
        binding.resultsRecyclerView.apply {
            adapter = videoAdapter
            layoutManager = linearLayoutManager
            addOnScrollListener(object : androidx.recyclerview.widget.RecyclerView.OnScrollListener() {
                override fun onScrolled(
                    recyclerView: androidx.recyclerview.widget.RecyclerView,
                    dx: Int,
                    dy: Int
                ) {
                    super.onScrolled(recyclerView, dx, dy)
                    if (dy <= 0 || isLoadingMore || nextPageToken.isNullOrEmpty() || currentQuery.isNullOrEmpty()) {
                        return
                    }
                    val totalItems = videoAdapter.itemCount
                    val lastVisibleItem = linearLayoutManager.findLastVisibleItemPosition()
                    if (totalItems > 0 && lastVisibleItem >= totalItems - 5) {
                        loadMoreResults()
                    }
                }
            })
        }
    }

    private fun setupSearchInput() {
        binding.searchButton.isEnabled = false
        binding.searchEditText.addTextChangedListener { text ->
            binding.searchButton.isEnabled = !text.isNullOrBlank()
        }

        binding.searchEditText.setOnEditorActionListener { _, actionId, event ->
            if (actionId == EditorInfo.IME_ACTION_SEARCH ||
                (event?.keyCode == KeyEvent.KEYCODE_ENTER && event.action == KeyEvent.ACTION_DOWN)
            ) {
                performSearch()
                true
            } else {
                false
            }
        }

        binding.searchButton.setOnClickListener {
            performSearch()
        }
    }

    private fun performSearch() {
        val query = binding.searchEditText.text?.toString()?.trim()
        if (query.isNullOrBlank()) {
            Toast.makeText(requireContext(), "Please enter a search query", Toast.LENGTH_SHORT).show()
            return
        }

        searchJob?.cancel()
        loadMoreJob?.cancel()
        isLoadingMore = false
        currentQuery = query
        nextPageToken = null
        allVideos.clear()
        videoAdapter.submitList(emptyList())
        binding.searchEditText.clearFocus()
        showLoadingState(message = "Searching...", keepResultsVisible = false)

        searchJob = viewLifecycleOwner.lifecycleScope.launch {
            val result = runCatching { youTubeApiService.searchVideos(query) }.getOrElse {
                Result.failure(it)
            }

            result.onSuccess { searchResult ->
                if (_binding == null || currentQuery != query) return@onSuccess
                applySearchResults(searchResult.videos, searchResult.nextPageToken, append = false)
            }

            result.onFailure { error ->
                if (_binding == null || currentQuery != query) return@onFailure
                showError("Search failed: ${error.message ?: "Unknown error"}")
            }
        }
    }

    private fun loadMoreResults() {
        val query = currentQuery ?: return
        val pageToken = nextPageToken ?: return
        if (loadMoreJob?.isActive == true) return

        isLoadingMore = true
        showLoadingState(message = "Loading more...", keepResultsVisible = true)

        loadMoreJob = viewLifecycleOwner.lifecycleScope.launch {
            try {
                val result = youTubeApiService.searchVideos(query, pageToken = pageToken)
                result.onSuccess { searchResult ->
                    if (_binding == null || currentQuery != query) return@onSuccess
                    applySearchResults(searchResult.videos, searchResult.nextPageToken, append = true)
                }
                result.onFailure { error ->
                    if (_binding == null || currentQuery != query) return@onFailure
                    Toast.makeText(
                        requireContext(),
                        "Failed to load more: ${error.message ?: "Unknown error"}",
                        Toast.LENGTH_SHORT
                    ).show()
                    binding.progressContainer.visibility = View.GONE
                }
            } catch (e: Exception) {
                if (_binding != null && currentQuery == query) {
                    binding.progressContainer.visibility = View.GONE
                    Toast.makeText(
                        requireContext(),
                        "Failed to load more: ${e.message ?: "Unknown error"}",
                        Toast.LENGTH_SHORT
                    ).show()
                }
            } finally {
                isLoadingMore = false
            }
        }
    }

    private fun applySearchResults(
        videos: List<YouTubeVideo>,
        upcomingPageToken: String?,
        append: Boolean
    ) {
        nextPageToken = upcomingPageToken
        if (append) {
            val existingIds = allVideos.mapTo(mutableSetOf()) { it.id }
            val freshVideos = videos.filter { existingIds.add(it.id) }
            allVideos.addAll(freshVideos)
        } else {
            allVideos.clear()
            allVideos.addAll(videos.distinctBy { it.id })
        }

        binding.progressContainer.visibility = View.GONE
        if (allVideos.isEmpty()) {
            showEmptyState(
                title = "No results found",
                subtitle = "Try a different title, artist, or paste a more specific search."
            )
            return
        }

        binding.emptyStateContainer.visibility = View.GONE
        binding.resultsRecyclerView.visibility = View.VISIBLE
        videoAdapter.submitList(allVideos.toList())
    }

    private fun showLoadingState(message: String, keepResultsVisible: Boolean) {
        binding.progressContainer.visibility = View.VISIBLE
        binding.progressText.text = message
        if (!keepResultsVisible) {
            binding.resultsRecyclerView.visibility = View.GONE
            binding.emptyStateContainer.visibility = View.GONE
        }
    }

    private fun showEmptyState(title: String, subtitle: String) {
        binding.progressContainer.visibility = View.GONE
        binding.resultsRecyclerView.visibility = View.GONE
        binding.emptyStateContainer.visibility = View.VISIBLE
        binding.emptyStateTitle.text = title
        binding.emptyStateSubtitle.text = subtitle
    }

    private fun showError(message: String) {
        showEmptyState(
            title = "Search unavailable",
            subtitle = message
        )
        Toast.makeText(requireContext(), message, Toast.LENGTH_LONG).show()
    }

    private fun openVideoPreview(video: YouTubeVideo) {
        try {
            val intent = Intent(requireContext(), YouTubeStreamingActivity::class.java).apply {
                putExtra(YouTubeStreamingActivity.EXTRA_VIDEO, video)
            }
            startActivity(intent)
        } catch (e: Exception) {
            Toast.makeText(
                requireContext(),
                "Unable to open player: ${e.message ?: "Unknown error"}",
                Toast.LENGTH_SHORT
            ).show()
        }
    }

    private fun handleDownloadClick(video: YouTubeVideo) {
        viewLifecycleOwner.lifecycleScope.launch {
            primeThumbnailCache(video)
        }

        val youTubeUrl = if (video.url.startsWith("http")) video.url else video.formattedUrl
        val opened = SealIntegration.openInSeal(requireContext(), youTubeUrl)
        if (opened) {
            Toast.makeText(requireContext(), "Opening Seal to download...", Toast.LENGTH_SHORT).show()
            return
        }

        androidx.appcompat.app.AlertDialog.Builder(requireContext())
            .setTitle("Install Seal")
            .setMessage("This app now hands downloads to Seal. Install it to continue?")
            .setPositiveButton("Install") { _, _ ->
                SealIntegration.promptInstall(requireContext())
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private suspend fun primeThumbnailCache(video: YouTubeVideo) {
        runCatching {
            val metadataExtractor = com.stash.opusplayer.utils.MetadataExtractor(requireContext())
            val thumbnailBase64 = metadataExtractor.downloadYouTubeThumbnail(video.id) ?: return
            val bytes = android.util.Base64.decode(thumbnailBase64, android.util.Base64.DEFAULT)
            val cache = com.stash.opusplayer.artwork.ArtworkCache(requireContext())
            val variants = listOf(
                com.stash.opusplayer.data.Song(0L, video.title, video.channelTitle, "YouTube", 0L, ""),
                com.stash.opusplayer.data.Song(0L, video.title, video.channelTitle, "Unknown Album", 0L, ""),
                com.stash.opusplayer.data.Song(0L, video.title, video.channelTitle, "", 0L, ""),
                com.stash.opusplayer.data.Song(0L, video.title, "Unknown Artist", "YouTube", 0L, ""),
                com.stash.opusplayer.data.Song(0L, video.title, "Unknown Artist", "Unknown Album", 0L, ""),
                com.stash.opusplayer.data.Song(0L, video.title, "Unknown Artist", "", 0L, "")
            )
            variants.forEach { song ->
                val file = cache.fileFor(song)
                if (!file.exists()) {
                    cache.saveJpeg(bytes, file)
                }
            }
            val titleOnlyFile = cache.fileForTitleOnly(video.title)
            if (!titleOnlyFile.exists()) {
                cache.saveJpeg(bytes, titleOnlyFile)
            }
        }
    }

    override fun onDestroyView() {
        searchJob?.cancel()
        loadMoreJob?.cancel()
        binding.resultsRecyclerView.adapter = null
        allVideos.clear()
        super.onDestroyView()
        _binding = null
    }
}
