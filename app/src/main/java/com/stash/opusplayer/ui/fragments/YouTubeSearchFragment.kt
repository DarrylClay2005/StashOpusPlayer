package com.stash.stashwave.ui.fragments

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.provider.DocumentsContract
import android.view.KeyEvent
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.widget.addTextChangedListener
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.stash.stashwave.data.DownloadRequest
import com.stash.stashwave.data.YouTubeVideo
import com.stash.stashwave.data.AudioFormat
import com.stash.stashwave.ui.dialogs.FormatSelectionDialog
import com.stash.stashwave.databinding.FragmentYoutubeSearchBinding
import com.stash.stashwave.network.YouTubeApiService
import com.stash.stashwave.service.VideoDownloadManager
import com.stash.stashwave.ui.adapters.YouTubeVideoAdapter
import kotlinx.coroutines.launch
import java.io.File

class YouTubeSearchFragment : Fragment() {

    private var _binding: FragmentYoutubeSearchBinding? = null
    private val binding get() = _binding!!

    private lateinit var youTubeApiService: YouTubeApiService
    private lateinit var videoAdapter: YouTubeVideoAdapter
    private lateinit var downloadManager: VideoDownloadManager
    private lateinit var linearLayoutManager: LinearLayoutManager

    // Pagination state
    private val allVideos = mutableListOf<YouTubeVideo>()
    private var currentQuery: String? = null
    private var nextPageToken: String? = null
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

        setupServices()
        setupRecyclerView()
        setupSearchInput()
        setupSealBanner()
    }

    private fun setupSealBanner() {
val installed = com.stash.stashwave.integration.SealIntegration.isInstalled(requireContext())
        if (installed) {
            binding.sealInfoBanner.visibility = View.VISIBLE
            binding.sealInfoText.text = "Downloads are handled by Seal and will open there. Tap Download to continue in Seal."
            binding.sealActionButton.visibility = View.GONE
        } else {
            binding.sealInfoBanner.visibility = View.VISIBLE
            binding.sealInfoText.text = "Install Seal to download videos reliably."
            binding.sealActionButton.visibility = View.VISIBLE
            binding.sealActionButton.text = "Install Seal"
            binding.sealActionButton.setOnClickListener {
com.stash.stashwave.integration.SealIntegration.promptInstall(requireContext())
            }
        }
    }

    private fun setupServices() {
        youTubeApiService = YouTubeApiService(requireContext())
        downloadManager = VideoDownloadManager(requireContext())
        
        // Observe download progress
        lifecycleScope.launch {
            downloadManager.downloadProgress.collect { progress ->
                videoAdapter.updateDownloadProgress(progress.videoId, progress)
            }
        }
    }

    private fun setupRecyclerView() {
        videoAdapter = YouTubeVideoAdapter(
            onVideoClick = { video ->
                // Open built-in YouTube player activity
                try {
val intent = Intent(requireContext(), com.stash.stashwave.ui.YouTubeStreamingActivity::class.java).apply {
                        putExtra(com.stash.stashwave.ui.YouTubeStreamingActivity.EXTRA_VIDEO, video)
                    }
                    startActivity(intent)
                } catch (e: Exception) {
                    Toast.makeText(requireContext(), "Unable to open player: ${e.message}", Toast.LENGTH_SHORT).show()
                }
            },
            onDownloadClick = { video ->
                handleDownloadClick(video)
            },
            onPreviewClick = { video ->
                // Also route preview to the in-app player for a consistent experience
                try {
val intent = Intent(requireContext(), com.stash.stashwave.ui.YouTubeStreamingActivity::class.java).apply {
                        putExtra(com.stash.stashwave.ui.YouTubeStreamingActivity.EXTRA_VIDEO, video)
                    }
                    startActivity(intent)
                } catch (e: Exception) {
                    Toast.makeText(requireContext(), "Unable to open player: ${e.message}", Toast.LENGTH_SHORT).show()
                }
            }
        )

        binding.resultsRecyclerView.apply {
            adapter = videoAdapter
            layoutManager = LinearLayoutManager(requireContext()).also { this@YouTubeSearchFragment.linearLayoutManager = it }
            addOnScrollListener(object : androidx.recyclerview.widget.RecyclerView.OnScrollListener() {
                override fun onScrolled(recyclerView: androidx.recyclerview.widget.RecyclerView, dx: Int, dy: Int) {
                    super.onScrolled(recyclerView, dx, dy)
                    if (dy <= 0) return
                    val total = videoAdapter.itemCount
                    val lastVisible = this@YouTubeSearchFragment.linearLayoutManager.findLastVisibleItemPosition()
                    val nearEnd = total > 0 && lastVisible >= total - 5
                    if (nearEnd && !isLoadingMore && !nextPageToken.isNullOrEmpty() && !currentQuery.isNullOrEmpty()) {
                        loadMoreResults()
                    }
                }
            })
        }
    }

    private fun setupSearchInput() {
        binding.searchEditText.addTextChangedListener { text ->
            // Enable/disable search button based on input
            binding.searchButton.isEnabled = !text.isNullOrBlank()
        }

        binding.searchEditText.setOnEditorActionListener { _, actionId, event ->
            if (actionId == EditorInfo.IME_ACTION_SEARCH || 
                (event?.keyCode == KeyEvent.KEYCODE_ENTER && event.action == KeyEvent.ACTION_DOWN)) {
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

        // Reset pagination state
        currentQuery = query
        nextPageToken = null
        allVideos.clear()

        // Hide keyboard
        binding.searchEditText.clearFocus()

        // Show progress
        binding.progressContainer.visibility = View.VISIBLE
        binding.progressText.text = "Searching..."
        binding.emptyStateContainer.visibility = View.GONE
        binding.resultsRecyclerView.visibility = View.GONE

        lifecycleScope.launch {
            try {
                val result = youTubeApiService.searchVideos(query)
                
                result.onSuccess { searchResult ->
                    binding.progressContainer.visibility = View.GONE
                    
                    if (searchResult.videos.isNotEmpty()) {
                        allVideos.addAll(searchResult.videos)
                        nextPageToken = searchResult.nextPageToken
                        videoAdapter.submitList(allVideos.toList())
                        binding.resultsRecyclerView.visibility = View.VISIBLE
                        binding.emptyStateContainer.visibility = View.GONE
                    } else {
                        showEmptyResults()
                    }
                }
                
                result.onFailure { error ->
                    binding.progressContainer.visibility = View.GONE
                    showError("Search failed: ${error.message}")
                }
                
            } catch (e: Exception) {
                binding.progressContainer.visibility = View.GONE
                showError("Search failed: ${e.message}")
            }
        }
    }

    private fun loadMoreResults() {
        val q = currentQuery ?: return
        val token = nextPageToken ?: return
        isLoadingMore = true

        // Optional: could show a small footer spinner; for now rely on smooth append
        lifecycleScope.launch {
            try {
                val result = youTubeApiService.searchVideos(q, pageToken = token)
                result.onSuccess { searchResult ->
                    nextPageToken = searchResult.nextPageToken
                    if (searchResult.videos.isNotEmpty()) {
                        val start = allVideos.size
                        allVideos.addAll(searchResult.videos)
                        // submit a new list instance to trigger DiffUtil
                        videoAdapter.submitList(allVideos.toList())
                        // Optionally scroll remains natural as user is at end
                    }
                }
                result.onFailure { error ->
                    Toast.makeText(requireContext(), "Failed to load more: ${error.message}", Toast.LENGTH_SHORT).show()
                }
            } catch (e: Exception) {
                Toast.makeText(requireContext(), "Failed to load more: ${e.message}", Toast.LENGTH_SHORT).show()
            } finally {
                isLoadingMore = false
            }
        }
    }

    private fun handleDownloadClick(video: YouTubeVideo) {
        // Pre-cache YouTube thumbnail into our artwork cache so playback shows cover art even if file tags lack artwork
        lifecycleScope.launch {
            try {
                val meta = com.stash.stashwave.utils.MetadataExtractor(requireContext())
                val b64 = meta.downloadYouTubeThumbnail(video.id)
                if (b64 != null) {
                    val bytes = android.util.Base64.decode(b64, android.util.Base64.DEFAULT)
                    val cache = com.stash.stashwave.artwork.ArtworkCache(requireContext())
                    // Save under a few likely variants so later scans can find it
                    val variants = listOf(
                        // Known channel as artist
                        com.stash.stashwave.data.Song(0L, video.title, video.channelTitle, "YouTube", 0L, ""),
                        com.stash.stashwave.data.Song(0L, video.title, video.channelTitle, "Unknown Album", 0L, ""),
                        com.stash.stashwave.data.Song(0L, video.title, video.channelTitle, "", 0L, ""),
                        // Unknown artist fallback (common after external downloads)
                        com.stash.stashwave.data.Song(0L, video.title, "Unknown Artist", "YouTube", 0L, ""),
                        com.stash.stashwave.data.Song(0L, video.title, "Unknown Artist", "Unknown Album", 0L, ""),
                        com.stash.stashwave.data.Song(0L, video.title, "Unknown Artist", "", 0L, "")
                    )
                    variants.forEach { s ->
                        val f = cache.fileFor(s)
                        if (!f.exists()) cache.saveJpeg(bytes, f)
                    }
                    // Also save by title-only key to improve hit rate for unknown tags
                    val tf = cache.fileForTitleOnly(video.title)
                    if (!tf.exists()) cache.saveJpeg(bytes, tf)
                }
            } catch (_: Exception) {}
        }

        // Simple handoff to Seal without trying to set download location
        val ytUrl = if (video.url.startsWith("http")) video.url else video.formattedUrl
        val opened = com.stash.stashwave.integration.SealIntegration.openInSeal(requireContext(), ytUrl)
        if (opened) {
            Toast.makeText(requireContext(), "Opening Seal to download…", Toast.LENGTH_SHORT).show()
        } else {
            // Prompt install if not available
            androidx.appcompat.app.AlertDialog.Builder(requireContext())
                .setTitle("Install Seal")
                .setMessage("This app uses Seal as the downloader. Install Seal to continue?")
                .setPositiveButton("Install") { _, _ ->
                    com.stash.stashwave.integration.SealIntegration.promptInstall(requireContext())
                }
                .setNegativeButton("Cancel", null)
                .show()
        }
    }
    

    private fun showEmptyResults() {
        binding.resultsRecyclerView.visibility = View.GONE
        binding.emptyStateContainer.visibility = View.VISIBLE
        // Update empty state text for no results
    }

    private fun showError(message: String) {
        binding.resultsRecyclerView.visibility = View.GONE
        binding.emptyStateContainer.visibility = View.VISIBLE
        Toast.makeText(requireContext(), message, Toast.LENGTH_LONG).show()
    }

    private fun sanitizeFileName(fileName: String): String {
        return fileName
            .replace(Regex("""[^a-zA-Z0-9._\-\s]"""), "_")
            .replace(Regex("""\s+"""), "_")
            .take(100)
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
