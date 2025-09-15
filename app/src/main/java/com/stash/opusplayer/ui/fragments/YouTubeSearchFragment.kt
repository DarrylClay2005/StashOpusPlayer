package com.stash.opusplayer.ui.fragments

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
import com.stash.opusplayer.data.DownloadRequest
import com.stash.opusplayer.data.YouTubeVideo
import com.stash.opusplayer.data.AudioFormat
import com.stash.opusplayer.ui.dialogs.FormatSelectionDialog
import com.stash.opusplayer.databinding.FragmentYoutubeSearchBinding
import com.stash.opusplayer.network.YouTubeApiService
import com.stash.opusplayer.service.VideoDownloadManager
import com.stash.opusplayer.ui.adapters.YouTubeVideoAdapter
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
                // Open video in browser or YouTube app
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(video.url))
                startActivity(intent)
            },
            onDownloadClick = { video ->
                handleDownloadClick(video)
            },
            onPreviewClick = { video ->
                // Open video in browser for preview
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(video.url))
                startActivity(intent)
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
        if (currentDownloadPath.isBlank()) {
            Toast.makeText(
                requireContext(),
                "Please select a download location first",
                Toast.LENGTH_SHORT
            ).show()
            return
        }

        // Show loading state
        binding.progressContainer.visibility = View.VISIBLE
        binding.progressText.text = "Loading audio formats..."

        lifecycleScope.launch {
            try {
                // Get available audio formats
                val formatsResult = youTubeApiService.getAudioFormats(video.id)
                
                binding.progressContainer.visibility = View.GONE
                
                formatsResult.onSuccess { formats ->
                    if (formats.isNotEmpty()) {
                        // Show format selection dialog
                        FormatSelectionDialog.show(
                            requireContext(),
                            video,
                            formats
                        ) { selectedFormat ->
                            startDownloadWithFormat(video, selectedFormat)
                        }
                    } else {
                        Toast.makeText(
                            requireContext(),
                            "No audio formats available for this video",
                            Toast.LENGTH_SHORT
                        ).show()
                    }
                }
                
                formatsResult.onFailure { error ->
                    Toast.makeText(
                        requireContext(),
                        "Failed to load audio formats: ${error.message}",
                        Toast.LENGTH_SHORT
                    ).show()
                }
                
            } catch (e: Exception) {
                binding.progressContainer.visibility = View.GONE
                Toast.makeText(
                    requireContext(),
                    "Error loading formats: ${e.message}",
                    Toast.LENGTH_SHORT
                ).show()
            }
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
