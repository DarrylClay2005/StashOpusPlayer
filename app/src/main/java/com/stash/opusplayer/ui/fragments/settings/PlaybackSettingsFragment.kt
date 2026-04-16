package com.stash.opusplayer.ui.fragments.settings

import android.content.ComponentName
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.AdapterView
import androidx.core.os.bundleOf
import androidx.media3.common.PlaybackParameters
import androidx.media3.session.MediaController
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors
import com.google.android.material.slider.Slider
import com.google.android.material.switchmaterial.SwitchMaterial
import com.stash.opusplayer.audio.EqualizerPreset
import com.stash.opusplayer.service.MusicService
import com.stash.opusplayer.ui.fragments.EqualizerFragment
import kotlin.math.roundToInt

class PlaybackSettingsFragment : NavigableSettingsFragment() {

    override val screenTitle: String = "Playback Settings"

    private var mediaController: MediaController? = null
    private var controllerFuture: ListenableFuture<MediaController>? = null

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        val (scrollView, content) = createSettingsPage(
            title = "Playback",
            subtitle = "Rebuilt controls for transport, loudness, transitions, and recovery tools."
        )

        buildPlaybackParameters(content)
        buildPlaybackBehavior(content)
        buildReplayGain(content)
        buildDiagnostics(content)

        return scrollView
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        connectController()
    }

    override fun onDestroyView() {
        super.onDestroyView()
        runCatching { mediaController?.release() }
        mediaController = null
        controllerFuture?.let { MediaController.releaseFuture(it) }
        controllerFuture = null
    }

    private fun buildPlaybackParameters(parent: ViewGroup) {
        val settings = settingsPrefs()
        val section = addSettingsSection(
            parent as android.widget.LinearLayout,
            "Playback Parameters",
            "Shape how the current track sounds without hunting through multiple broken tabs."
        )

        addSliderControl(
            section,
            title = "Playback speed",
            summary = "Adjust tempo from slow study mode to quick preview mode.",
            valueFrom = 0.25f,
            valueTo = 2.5f,
            stepSize = 0.05f,
            initialValue = settings.getFloat("playback_speed", 1.0f).coerceIn(0.25f, 2.5f),
            formatter = { value -> String.format("%.2fx", value) }
        ) { value, fromUser ->
            if (fromUser) {
                settings.edit().putFloat("playback_speed", value).apply()
                mediaController?.let { controller ->
                    runCatching {
                        val current = controller.playbackParameters
                        controller.playbackParameters = PlaybackParameters(value, current.pitch)
                    }
                }
            }
        }

        val savedSemitones = settings.getInt("pitch_semitones", 0).coerceIn(-12, 12)
        addSliderControl(
            section,
            title = "Pitch shift",
            summary = "Move the key without changing the track order or reopening the player.",
            valueFrom = -12f,
            valueTo = 12f,
            stepSize = 1f,
            initialValue = savedSemitones.toFloat(),
            formatter = { value ->
                val semitones = value.roundToInt()
                val factor = Math.pow(2.0, semitones / 12.0).toFloat()
                "${semitones} st  (${String.format("x%.3f", factor)})"
            }
        ) { value, fromUser ->
            if (fromUser) {
                val semitones = value.roundToInt()
                val factor = Math.pow(2.0, semitones / 12.0).toFloat()
                settings.edit()
                    .putInt("pitch_semitones", semitones)
                    .putFloat("pitch_factor", factor)
                    .apply()
                mediaController?.let { controller ->
                    runCatching {
                        val current = controller.playbackParameters
                        controller.playbackParameters = PlaybackParameters(current.speed, factor)
                    }
                }
            }
        }

        val savedPreset = settings.getInt("reverb_preset", 0).coerceIn(0, 6)
        addSliderControl(
            section,
            title = "Reverb",
            summary = "Use a lighter preset curve instead of the old unlabeled percentage slider.",
            valueFrom = 0f,
            valueTo = 6f,
            stepSize = 1f,
            initialValue = savedPreset.toFloat(),
            formatter = { value -> reverbLabelForPreset(value.roundToInt()) }
        ) { value, fromUser ->
            if (fromUser) {
                val preset = value.roundToInt().coerceIn(0, 6)
                settings.edit().putInt("reverb_preset", preset).apply()
                mediaController?.let { controller ->
                    runCatching {
                        controller.sendCustomCommand(
                            SessionCommand("SET_REVERB", Bundle.EMPTY),
                            bundleOf("preset" to preset)
                        )
                    }
                }
            }
        }

        addBodyText(
            section,
            "Pitch and speed are saved immediately, and the active session updates live when the service is connected."
        )
    }

    private fun buildPlaybackBehavior(parent: ViewGroup) {
        val settings = settingsPrefs()
        val section = addSettingsSection(
            parent as android.widget.LinearLayout,
            "Playback Behavior",
            "Fixes the day-to-day playback logic that should have been accessible from one screen all along."
        )

        addSliderControl(
            section,
            title = "App volume",
            summary = "This is the player’s internal output trim before Android’s system volume.",
            valueFrom = 0f,
            valueTo = 100f,
            stepSize = 1f,
            initialValue = settings.getFloat("app_volume", 1.0f).coerceIn(0f, 1f) * 100f,
            formatter = { value ->
                val ui = value.roundToInt()
                val effective = Math.pow((ui / 100f).toDouble(), 2.0).toFloat()
                "$ui%  (effective ${(effective * 100).roundToInt()}%)"
            }
        ) { value, fromUser ->
            if (fromUser) {
                val volume = (value / 100f).coerceIn(0f, 1f)
                settings.edit().putFloat("app_volume", volume).apply()
                sendCustomCommand("SET_APP_VOLUME", bundleOf("volume" to volume))
            }
        }

        addSwitchControl(
            section,
            title = "Audio focus",
            summary = "Pause or duck when calls, navigation, or other apps interrupt playback.",
            checked = settings.getBoolean("audio_focus_enabled", true)
        ) { enabled ->
            settings.edit().putBoolean("audio_focus_enabled", enabled).apply()
            sendCustomCommand("SET_AUDIO_FOCUS", bundleOf("enabled" to enabled))
        }

        val crossfadeToggle = addSwitchControl(
            section,
            title = "Crossfade between tracks",
            summary = "Blend the end of one song into the next without relying on the old hidden controls.",
            checked = settings.getBoolean("crossfade_enabled", false)
        ) { enabled ->
            settings.edit().putBoolean("crossfade_enabled", enabled).apply()
            sendCustomCommand("SET_CROSSFADE_ENABLED", bundleOf("enabled" to enabled))
        }

        val (crossfadeSlider, _) = addSliderControl(
            section,
            title = "Crossfade duration",
            summary = "How long the overlap should last when crossfade is enabled.",
            valueFrom = 0f,
            valueTo = 5000f,
            stepSize = 100f,
            initialValue = settings.getLong("crossfade_duration_ms", 1000L).coerceIn(0L, 5000L).toFloat(),
            formatter = { value -> "${value.roundToInt()} ms" }
        ) { value, fromUser ->
            if (fromUser) {
                val durationMs = value.roundToInt().toLong().coerceIn(0L, 5000L)
                settings.edit().putLong("crossfade_duration_ms", durationMs).apply()
                sendCustomCommand("SET_CROSSFADE_DURATION", bundleOf("duration_ms" to durationMs))
            }
        }
        crossfadeSlider.isEnabled = crossfadeToggle.isChecked
        crossfadeToggle.setOnCheckedChangeListener { _, enabled ->
            crossfadeSlider.isEnabled = enabled
            settings.edit().putBoolean("crossfade_enabled", enabled).apply()
            sendCustomCommand("SET_CROSSFADE_ENABLED", bundleOf("enabled" to enabled))
        }

        addSwitchControl(
            section,
            title = "True crossfade engine",
            summary = "Use the dual-player overlap path. Turn this off if you hear queue transition glitches.",
            checked = settings.getBoolean("experimental_true_crossfade", true)
        ) { enabled ->
            settings.edit().putBoolean("experimental_true_crossfade", enabled).apply()
        }

        addSwitchControl(
            section,
            title = "Crossfade polling guard",
            summary = "Keep the overlap watcher active. Disable it if track switches race on your device.",
            checked = settings.getBoolean("crossfade_polling_enabled", true)
        ) { enabled ->
            settings.edit().putBoolean("crossfade_polling_enabled", enabled).apply()
            sendCustomCommand("SET_CROSSFADE_POLLING_ENABLED", bundleOf("enabled" to enabled))
        }

        addSwitchControl(
            section,
            title = "Skip silence",
            summary = "Trim silent gaps during spoken word or long dead-air intros.",
            checked = settings.getBoolean("skip_silence_enabled", false)
        ) { enabled ->
            settings.edit().putBoolean("skip_silence_enabled", enabled).apply()
        }

        addSwitchControl(
            section,
            title = "Exact seeks",
            summary = "Prefer precise seeking for tighter gapless behavior.",
            checked = settings.getBoolean("exact_seeks", true)
        ) { enabled ->
            settings.edit().putBoolean("exact_seeks", enabled).apply()
        }
    }

    private fun buildReplayGain(parent: ViewGroup) {
        val settings = settingsPrefs()
        val section = addSettingsSection(
            parent as android.widget.LinearLayout,
            "ReplayGain",
            "Normalize perceived loudness without flattening the whole app."
        )

        addSwitchControl(
            section,
            title = "Enable ReplayGain",
            summary = "Apply loudness metadata automatically when tags are available.",
            checked = settings.getBoolean("replaygain_enabled", false)
        ) { enabled ->
            settings.edit().putBoolean("replaygain_enabled", enabled).apply()
        }

        val modeEntries = listOf("Track gain", "Album gain")
        val modeSpinner = addSpinnerControl(
            section,
            title = "Gain mode",
            summary = "Track mode keeps individual songs even. Album mode preserves record dynamics.",
            entries = modeEntries
        )
        val savedMode = settings.getString("replaygain_mode", "track") ?: "track"
        var modeHydrated = false
        modeSpinner.setSelection(if (savedMode == "album") 1 else 0)
        modeSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                if (!modeHydrated) {
                    modeHydrated = true
                    return
                }
                settings.edit()
                    .putString("replaygain_mode", if (position == 1) "album" else "track")
                    .apply()
            }

            override fun onNothingSelected(parent: AdapterView<*>?) = Unit
        }

        addSliderControl(
            section,
            title = "Preamp",
            summary = "Global offset applied before ReplayGain correction.",
            valueFrom = -12f,
            valueTo = 12f,
            stepSize = 0.5f,
            initialValue = settings.getFloat("replaygain_preamp_db", 0f).coerceIn(-12f, 12f),
            formatter = { value -> String.format("%.1f dB", value) }
        ) { value, fromUser ->
            if (fromUser) {
                settings.edit().putFloat("replaygain_preamp_db", value).apply()
            }
        }

        addSliderControl(
            section,
            title = "Fallback gain",
            summary = "Used when a file has no ReplayGain tags.",
            valueFrom = -12f,
            valueTo = 12f,
            stepSize = 0.5f,
            initialValue = settings.getFloat("replaygain_fallback_db", 0f).coerceIn(-12f, 12f),
            formatter = { value -> String.format("%.1f dB", value) }
        ) { value, fromUser ->
            if (fromUser) {
                settings.edit().putFloat("replaygain_fallback_db", value).apply()
            }
        }

        addSwitchControl(
            section,
            title = "Prevent clipping",
            summary = "Clamp boosts when the corrected gain would overload the output.",
            checked = settings.getBoolean("replaygain_prevent_clipping", true)
        ) { enabled ->
            settings.edit().putBoolean("replaygain_prevent_clipping", enabled).apply()
        }

        addSwitchControl(
            section,
            title = "Allow positive gain",
            summary = "Permit boosts on quiet files when the device can support them cleanly.",
            checked = settings.getBoolean("replaygain_allow_boost", false)
        ) { enabled ->
            settings.edit().putBoolean("replaygain_allow_boost", enabled).apply()
        }
    }

    private fun buildDiagnostics(parent: ViewGroup) {
        val section = addSettingsSection(
            parent as android.widget.LinearLayout,
            "Recovery Tools",
            "These actions help when the playback stack gets into a bad state."
        )

        addActionButton(section, "Open equalizer") {
            navigateToSettingsScreen(EqualizerFragment())
        }

        addActionButton(section, "Reset to max volume diagnostic", outlined = true) {
            val settings = settingsPrefs()
            settings.edit()
                .putFloat("app_volume", 1.0f)
                .putBoolean("crossfade_enabled", false)
                .putLong("crossfade_duration_ms", 0L)
                .putBoolean("skip_silence_enabled", false)
                .putBoolean("replaygain_enabled", false)
                .putInt("reverb_preset", 0)
                .apply()
            defaultPrefs().edit()
                .putBoolean("equalizer_enabled", false)
                .putString("equalizer_preset", EqualizerPreset.NORMAL.name)
                .putInt("bass_boost_strength", 0)
                .putInt("virtualizer_strength", 0)
                .putInt("loudness_enhancer_gain", 0)
                .putString("custom_eq_bands", null)
                .apply()
            sendCustomCommand("AUDIO_TEST_MAX_VOLUME", Bundle.EMPTY)
            android.widget.Toast.makeText(
                requireContext(),
                "Playback reset to a clean max-volume diagnostic state.",
                android.widget.Toast.LENGTH_LONG
            ).show()
        }

        addActionButton(section, "Dump playback state", outlined = true) {
            sendCustomCommand("DUMP_PLAYBACK_STATE", Bundle.EMPTY)
            android.widget.Toast.makeText(
                requireContext(),
                "Playback state was sent to logcat.",
                android.widget.Toast.LENGTH_SHORT
            ).show()
        }
    }

    private fun connectController() {
        runCatching {
            val token = SessionToken(
                requireContext(),
                ComponentName(requireContext(), MusicService::class.java)
            )
            controllerFuture = MediaController.Builder(requireContext(), token).buildAsync()
            controllerFuture?.addListener(
                {
                    mediaController = runCatching { controllerFuture?.get() }.getOrNull()
                },
                MoreExecutors.directExecutor()
            )
        }
    }

    private fun sendCustomCommand(command: String, bundle: Bundle) {
        mediaController?.let { controller ->
            runCatching {
                controller.sendCustomCommand(SessionCommand(command, Bundle.EMPTY), bundle)
            }
        }
    }

    private fun reverbLabelForPreset(preset: Int): String {
        return when (preset) {
            0 -> "Off"
            1 -> "Small room"
            2 -> "Medium room"
            3 -> "Large room"
            4 -> "Hall"
            5 -> "Plate"
            else -> "Deep space"
        }
    }
}
