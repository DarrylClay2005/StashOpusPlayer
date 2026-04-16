package com.stash.opusplayer.ui.fragments.settings

import android.content.Intent
import android.os.Bundle
import android.text.InputType
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.AdapterView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.lifecycle.lifecycleScope
import com.stash.opusplayer.activity.DownloadServiceSettingsActivity
import com.stash.opusplayer.service.CustomYouTubeExtractionService
import com.stash.opusplayer.service.ExtractionServiceConfig
import com.stash.opusplayer.youtube.YouTubePlaybackBackend
import com.stash.opusplayer.youtube.YouTubePlaybackSettings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class StreamingSettingsFragment : NavigableSettingsFragment() {

    override val screenTitle: String = "Streaming & Downloads"

    private lateinit var serviceStatusView: TextView
    private lateinit var lavalinkUrlInput: com.google.android.material.textfield.TextInputEditText
    private lateinit var lavalinkPasswordInput: com.google.android.material.textfield.TextInputEditText

    private val backendValues = listOf(
        YouTubePlaybackBackend.AUTO,
        YouTubePlaybackBackend.YT_DLP,
        YouTubePlaybackBackend.LAVALINK
    )

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        val (scrollView, content) = createSettingsPage(
            title = "Streaming",
            subtitle = "Stabilized YouTube playback, Lavalink routing, and download service control."
        )

        buildYouTubeSection(content)
        buildDownloadSection(content)

        return scrollView
    }

    override fun onResume() {
        super.onResume()
        updateServiceStatus()
    }

    private fun buildYouTubeSection(parent: LinearLayout) {
        val section = addSettingsSection(
            parent,
            "YouTube Playback",
            "Save the API key, choose the playback backend, and keep the Lavalink path visible."
        )

        val apiKeyInput = addTextInputControl(
            section,
            title = "YouTube Data API key",
            summary = "Used for search and metadata when you want a personal quota instead of the baked-in fallback.",
            hint = "Paste your YouTube API key",
            initialText = settingsPrefs().getString("user_youtube_api_key", "").orEmpty()
        )

        val backendSpinner = addSpinnerControl(
            section,
            title = "Playback backend",
            summary = "Auto prefers the Lavalink node first, then falls back to local yt-dlp extraction.",
            entries = listOf(
                "Auto (Lavalink -> yt-dlp)",
                "yt-dlp only",
                "Lavalink compatible"
            )
        )
        backendSpinner.setSelection(
            backendValues.indexOf(YouTubePlaybackSettings.getBackend(requireContext())).coerceAtLeast(0)
        )

        lavalinkUrlInput = addTextInputControl(
            section,
            title = "Lavalink URL",
            summary = "Base URL for your node, for example http://192.168.1.10:2333.",
            hint = "http://host:port",
            initialText = YouTubePlaybackSettings.getLavalinkUrl(requireContext())
        )

        lavalinkPasswordInput = addTextInputControl(
            section,
            title = "Lavalink password",
            summary = "Password used by your node. Leave it blank only if your server is configured that way.",
            hint = "youshallnotpass",
            initialText = YouTubePlaybackSettings.getLavalinkPassword(requireContext()),
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
        )

        val updateLavalinkVisibility = {
            val backend = backendValues[backendSpinner.selectedItemPosition]
            val visible = backend != YouTubePlaybackBackend.YT_DLP
            val visibility = if (visible) View.VISIBLE else View.GONE
            ((lavalinkUrlInput.parent as? View)?.parent as? View)?.visibility = visibility
            ((lavalinkPasswordInput.parent as? View)?.parent as? View)?.visibility = visibility
        }
        updateLavalinkVisibility()
        backendSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                updateLavalinkVisibility()
            }

            override fun onNothingSelected(parent: AdapterView<*>?) = Unit
        }

        addActionButton(section, "Save playback settings") {
            val backend = backendValues[backendSpinner.selectedItemPosition]
            val lavalinkUrl = lavalinkUrlInput.text?.toString().orEmpty()
            val lavalinkPassword = lavalinkPasswordInput.text?.toString().orEmpty()

            if (backend == YouTubePlaybackBackend.LAVALINK && YouTubePlaybackSettings.normalizeBaseUrl(lavalinkUrl).isBlank()) {
                Toast.makeText(requireContext(), "Enter a Lavalink URL before forcing Lavalink mode.", Toast.LENGTH_LONG).show()
                return@addActionButton
            }

            settingsPrefs().edit()
                .putString("user_youtube_api_key", apiKeyInput.text?.toString().orEmpty().trim())
                .apply()
            YouTubePlaybackSettings.setBackend(requireContext(), backend)
            YouTubePlaybackSettings.setLavalinkUrl(requireContext(), lavalinkUrl)
            YouTubePlaybackSettings.setLavalinkPassword(requireContext(), lavalinkPassword)
            Toast.makeText(requireContext(), "YouTube playback settings saved.", Toast.LENGTH_SHORT).show()
        }

        addActionButton(section, "Update bundled yt-dlp", outlined = true) {
            val service = CustomYouTubeExtractionService(requireContext())
            lifecycleScope.launch {
                Toast.makeText(requireContext(), "Updating yt-dlp...", Toast.LENGTH_SHORT).show()
                val result = withContext(Dispatchers.IO) { service.updateYtDlp() }
                Toast.makeText(
                    requireContext(),
                    if (result.isSuccess) "yt-dlp updated successfully." else "yt-dlp update failed.",
                    Toast.LENGTH_LONG
                ).show()
            }
        }
    }

    private fun buildDownloadSection(parent: LinearLayout) {
        val section = addSettingsSection(
            parent,
            "Download Service",
            "Keep the extractor route visible and testable instead of hiding it deep in the legacy screen."
        )

        serviceStatusView = addBodyText(section, "Checking current service...")
        updateServiceStatus()

        addSwitchControl(
            section,
            title = "Auto-detect local extractor",
            summary = "Search the current network for a compatible local /quick endpoint.",
            checked = ExtractionServiceConfig.isAutoDetectEnabled(requireContext())
        ) { enabled ->
            ExtractionServiceConfig.setAutoDetectEnabled(requireContext(), enabled)
            updateServiceStatus()
        }

        val manualServiceInput = addTextInputControl(
            section,
            title = "Manual extractor URL",
            summary = "Use a direct /quick endpoint when you host your own extraction service.",
            hint = "http://host:8083/quick",
            initialText = ExtractionServiceConfig.getManualServiceUrl(requireContext())
        )

        addActionButton(section, "Save download service") {
            ExtractionServiceConfig.setManualServiceUrl(
                requireContext(),
                manualServiceInput.text?.toString().orEmpty()
            )
            updateServiceStatus()
            Toast.makeText(requireContext(), "Download service saved.", Toast.LENGTH_SHORT).show()
        }

        addActionButton(section, "Test current service", outlined = true) {
            lifecycleScope.launch {
                serviceStatusView.text = "Testing ${ExtractionServiceConfig.getServiceUrl(requireContext())}..."
                val healthy = withContext(Dispatchers.IO) {
                    ExtractionServiceConfig.testServiceConnectivity(requireContext())
                }
                serviceStatusView.text = if (healthy) {
                    "Service ready: ${ExtractionServiceConfig.getServiceUrl(requireContext())}"
                } else {
                    "Current service is unreachable: ${ExtractionServiceConfig.getServiceUrl(requireContext())}"
                }
            }
        }

        addActionButton(section, "Open advanced service manager", outlined = true) {
            startActivity(Intent(requireContext(), DownloadServiceSettingsActivity::class.java))
        }
    }

    private fun updateServiceStatus() {
        if (!this::serviceStatusView.isInitialized) {
            return
        }
        lifecycleScope.launch {
            val serviceUrl = ExtractionServiceConfig.getServiceUrl(requireContext())
            val healthy = withContext(Dispatchers.IO) {
                ExtractionServiceConfig.testServiceConnectivity(requireContext())
            }
            serviceStatusView.text = if (healthy) {
                "Current service: $serviceUrl"
            } else {
                "Current service is not reachable right now: $serviceUrl"
            }
        }
    }
}
