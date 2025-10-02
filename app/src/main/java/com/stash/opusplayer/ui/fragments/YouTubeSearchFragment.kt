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

    private var currentDownloadPath: String = ""

    private val directoryPickerLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            result.data?.data?.let { uri ->
                handleDirectorySelection(uri)
            }
        }
    }

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
        setupLocationSelector()
        initializeDefaultDownloadPath()
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
        youTubeApiService = YouTubeApiService()
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
            layoutManager = LinearLayoutManager(requireContext())
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

    private fun setupLocationSelector() {
        binding.selectLocationButton.setOnClickListener {
            openDirectoryPicker()
        }
    }

    private fun initializeDefaultDownloadPath() {
        currentDownloadPath = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "Music"
        ).absolutePath
        
        updateLocationDisplay()
    }

    private fun openDirectoryPicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            // Set initial directory to current download path if possible
            if (currentDownloadPath.isNotEmpty()) {
                val uri = Uri.parse("file://$currentDownloadPath")
                putExtra(DocumentsContract.EXTRA_INITIAL_URI, uri)
            }
        }
        directoryPickerLauncher.launch(intent)
    }

    private fun handleDirectorySelection(uri: Uri) {
        try {
            // Take persistent permission
            requireContext().contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )

            // Convert URI to path if possible, or store URI string
            currentDownloadPath = uri.toString()
            updateLocationDisplay()
            
            Toast.makeText(
                requireContext(),
                "Download location updated",
                Toast.LENGTH_SHORT
            ).show()
        } catch (e: Exception) {
            Toast.makeText(
                requireContext(),
                "Failed to set download location: ${e.message}",
                Toast.LENGTH_SHORT
            ).show()
        }
    }

    private fun updateLocationDisplay() {
        val displayPath = when {
            currentDownloadPath.startsWith("content://") -> {
                // Extract readable path from content URI
                "Selected folder"
            }
            currentDownloadPath.contains("/storage/emulated/0/") -> {
                currentDownloadPath.replace("/storage/emulated/0/", "")
            }
            else -> {
                File(currentDownloadPath).name
            }
        }
        binding.downloadLocationText.text = displayPath
    }

    private fun performSearch() {
        val query = binding.searchEditText.text?.toString()?.trim()
        if (query.isNullOrBlank()) {
            Toast.makeText(requireContext(), "Please enter a search query", Toast.LENGTH_SHORT).show()
            return
        }

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
                        videoAdapter.submitList(searchResult.videos)
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

        // Sole downloader: delegate to Seal app
        val url = video.formattedUrl
        val opened = com.stash.stashwave.integration.SealIntegration.openInSeal(requireContext(), url)
        if (opened) {
            Toast.makeText(requireContext(), "Opening Seal to download...", Toast.LENGTH_SHORT).show()
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
    
    private fun startDownloadWithFormat(video: YouTubeVideo, format: AudioFormat) {
        val downloadRequest = DownloadRequest(
            video = video,
            downloadPath = currentDownloadPath,
            selectedFormat = format,
            audioOnly = true
        )

        lifecycleScope.launch {
            try {
                downloadManager.startDownload(downloadRequest)
                Toast.makeText(
                    requireContext(),
                    "Download started: ${video.title} (${format.displayName})",
                    Toast.LENGTH_SHORT
                ).show()
            } catch (e: Exception) {
                Toast.makeText(
                    requireContext(),
                    "Failed to start download: ${e.message}",
                    Toast.LENGTH_SHORT
                ).show()
            }
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

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
