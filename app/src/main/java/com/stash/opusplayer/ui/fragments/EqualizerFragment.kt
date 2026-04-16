package com.stash.opusplayer.ui.fragments

import android.content.ComponentName
import android.os.Bundle
import android.view.LayoutInflater
import android.view.MenuItem
import android.view.View
import android.view.ViewGroup
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.os.bundleOf
import androidx.fragment.app.Fragment
import androidx.media3.session.MediaController
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionToken
import androidx.preference.PreferenceManager
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors
import com.stash.opusplayer.audio.EqualizerManager
import com.stash.opusplayer.audio.EqualizerPreset
import com.stash.opusplayer.databinding.FragmentEqualizerBinding
import com.stash.opusplayer.service.MusicService
import com.stash.opusplayer.ui.appearance.ThemeManager

class EqualizerFragment : Fragment() {

    private var _binding: FragmentEqualizerBinding? = null
    private val binding get() = _binding!!

    private var equalizerManager: EqualizerManager? = null
    private var mediaController: MediaController? = null
    private var controllerFuture: ListenableFuture<MediaController>? = null
    private val bandSliders = mutableListOf<SeekBar>()
    private val bandLabels = mutableListOf<TextView>()
    private var isHydratingUi = false
    private var currentBandRange: Pair<Int, Int> = Pair(-1500, 1500)
    private val defaultPrefs by lazy { PreferenceManager.getDefaultSharedPreferences(requireContext()) }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentEqualizerBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        @Suppress("DEPRECATION")
        run { setHasOptionsMenu(true) }

        (requireActivity() as? AppCompatActivity)?.supportActionBar?.apply {
            setDisplayHomeAsUpEnabled(true)
            setDisplayShowHomeEnabled(true)
            title = "Equalizer"
        }

        equalizerManager = EqualizerManager(requireContext())
        applyAdaptiveChrome()
        setupPresetSpinner()
        setupEffectsControls()
        setupListeners()
        setupEqualizerBands()
        loadPrefsIntoUi()
        connectToMediaController()
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return if (item.itemId == android.R.id.home) {
            parentFragmentManager.popBackStack()
            true
        } else {
            super.onOptionsItemSelected(item)
        }
    }

    private fun applyAdaptiveChrome() {
        val context = requireContext()
        binding.equalizerTitle.textSize = ThemeManager.scaleSp(context, 19f)
        binding.bassBoostValue.textSize = ThemeManager.scaleSp(context, 12f)
        binding.virtualizerValue.textSize = ThemeManager.scaleSp(context, 12f)
    }

    private fun setupPresetSpinner() {
        val presets = EqualizerPreset.values().map { preset ->
            preset.name.replace("_", " ").lowercase().replaceFirstChar { it.uppercaseChar() }
        }
        val adapter = ArrayAdapter(requireContext(), android.R.layout.simple_spinner_item, presets)
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        binding.presetSpinner.adapter = adapter
    }

    private fun setupEffectsControls() {
        binding.bassBoostSlider.max = 1000
        binding.bassBoostSlider.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                if (!fromUser) return
                binding.bassBoostValue.text = "${progress / 10}%"
                markEqualizerEnabledLocally()
                defaultPrefs.edit().putInt("bass_boost_strength", progress).apply()
                sendCustomCommand("SET_BASS_BOOST", bundleOf("strength" to progress))
            }

            override fun onStartTrackingTouch(seekBar: SeekBar?) = Unit
            override fun onStopTrackingTouch(seekBar: SeekBar?) = Unit
        })

        binding.virtualizerSlider.max = 1000
        binding.virtualizerSlider.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                if (!fromUser) return
                binding.virtualizerValue.text = "${progress / 10}%"
                markEqualizerEnabledLocally()
                defaultPrefs.edit().putInt("virtualizer_strength", progress).apply()
                sendCustomCommand("SET_VIRTUALIZER", bundleOf("strength" to progress))
            }

            override fun onStartTrackingTouch(seekBar: SeekBar?) = Unit
            override fun onStopTrackingTouch(seekBar: SeekBar?) = Unit
        })
    }

    private fun setupListeners() {
        binding.equalizerSwitch.setOnCheckedChangeListener { _, isChecked ->
            updateBandControlsEnabled(isChecked)
            defaultPrefs.edit().putBoolean("equalizer_enabled", isChecked).apply()
            if (isHydratingUi) return@setOnCheckedChangeListener
            sendCustomCommand("SET_EQ_ENABLED", bundleOf("enabled" to isChecked))
        }

        binding.presetSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                val preset = EqualizerPreset.values()[position]
                loadPreviewForPreset(preset)
                defaultPrefs.edit().putString("equalizer_preset", preset.name).apply()
                if (isHydratingUi) return
                markEqualizerEnabledLocally()
                sendCustomCommand("SET_EQ_PRESET", bundleOf("preset" to preset.name), refreshState = true)
            }

            override fun onNothingSelected(parent: AdapterView<*>?) = Unit
        }
    }

    private fun setupEqualizerBands(
        numberOfBands: Int = equalizerManager?.getNumberOfBands() ?: 5,
        range: Pair<Int, Int> = equalizerManager?.getBandRange() ?: Pair(-1500, 1500),
        frequencies: IntArray? = null,
        levels: FloatArray? = null
    ) {
        currentBandRange = range
        binding.bandsContainer.removeAllViews()
        bandSliders.clear()
        bandLabels.clear()

        for (index in 0 until numberOfBands) {
            val frequency = frequencies?.getOrNull(index) ?: equalizerManager?.getBandFrequency(index) ?: 0
            val level = levels?.getOrNull(index) ?: 0f
            binding.bandsContainer.addView(createBandView(index, range, frequency, level))
        }
    }

    private fun createBandView(
        bandIndex: Int,
        range: Pair<Int, Int>,
        frequency: Int,
        initialLevel: Float
    ): View {
        val context = requireContext()
        val horizontalGap = ThemeManager.scaleDp(context, 4)
        val sliderHeight = ThemeManager.scaleDp(context, 156)

        val bandLayout = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                0,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                1f
            ).apply {
                setMargins(horizontalGap, 0, horizontalGap, 0)
            }
        }

        val frequencyLabel = TextView(context).apply {
            text = formatFrequency(frequency)
            textSize = ThemeManager.scaleSp(context, 10f)
            gravity = android.view.Gravity.CENTER
        }

        val levelLabel = TextView(context).apply {
            text = "${String.format("%.1f", initialLevel)} dB"
            textSize = ThemeManager.scaleSp(context, 9f)
            gravity = android.view.Gravity.CENTER
        }

        val bandSlider = SeekBar(context).apply {
            max = range.second - range.first
            progress = ((initialLevel * 1000f).toInt().coerceIn(range.first, range.second) - range.first)
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                sliderHeight
            )

            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                    if (!fromUser) return
                    val level = (progress + range.first).toFloat() / 1000f
                    levelLabel.text = "${String.format("%.1f", level)} dB"
                    promotePresetSelectionToCustom()
                    markEqualizerEnabledLocally()
                    persistCurrentCustomBandLevels()
                    sendCustomCommand(
                        "SET_EQ_BAND",
                        bundleOf("band" to bandIndex, "level" to level)
                    )
                }

                override fun onStartTrackingTouch(seekBar: SeekBar?) = Unit
                override fun onStopTrackingTouch(seekBar: SeekBar?) = Unit
            })
        }

        bandSliders.add(bandSlider)
        bandLabels.add(levelLabel)

        bandLayout.addView(frequencyLabel)
        bandLayout.addView(bandSlider)
        bandLayout.addView(levelLabel)
        return bandLayout
    }

    private fun connectToMediaController() {
        val token = SessionToken(requireContext(), ComponentName(requireContext(), MusicService::class.java))
        controllerFuture = MediaController.Builder(requireContext(), token).buildAsync()
        controllerFuture?.addListener({
            val controller = runCatching { controllerFuture?.get() }.getOrNull() ?: return@addListener
            mediaController = controller
            requestLiveEqualizerState()
        }, MoreExecutors.directExecutor())
    }

    private fun loadPrefsIntoUi() {
        val prefs = defaultPrefs
        val enabled = prefs.getBoolean("equalizer_enabled", false)
        val presetName = prefs.getString("equalizer_preset", EqualizerPreset.NORMAL.name)
            ?: EqualizerPreset.NORMAL.name
        val preset = runCatching { EqualizerPreset.valueOf(presetName) }.getOrDefault(EqualizerPreset.NORMAL)
        val presetIndex = EqualizerPreset.values().indexOf(preset).coerceAtLeast(0)

        isHydratingUi = true
        binding.equalizerSwitch.isChecked = enabled
        binding.presetSpinner.setSelection(presetIndex)
        binding.bassBoostSlider.progress = prefs.getInt("bass_boost_strength", 0)
        binding.bassBoostValue.text = "${binding.bassBoostSlider.progress / 10}%"
        binding.virtualizerSlider.progress = prefs.getInt("virtualizer_strength", 0)
        binding.virtualizerValue.text = "${binding.virtualizerSlider.progress / 10}%"
        isHydratingUi = false

        updateBandControlsEnabled(enabled)
        loadPreviewForPreset(preset)
    }

    private fun requestLiveEqualizerState() {
        val controller = mediaController ?: return
        val future = controller.sendCustomCommand(SessionCommand("GET_EQ_STATE", Bundle.EMPTY), Bundle.EMPTY)
        future.addListener({
            val result = runCatching { future.get() }.getOrNull() ?: return@addListener
            val bundle = runCatching { result.extras }.getOrNull() ?: Bundle.EMPTY
            activity?.runOnUiThread {
                if (_binding == null) return@runOnUiThread
                applyLiveState(bundle)
            }
        }, MoreExecutors.directExecutor())
    }

    private fun applyLiveState(bundle: Bundle) {
        val enabled = bundle.getBoolean("enabled", false)
        val presetName = bundle.getString("preset", EqualizerPreset.NORMAL.name) ?: EqualizerPreset.NORMAL.name
        val preset = runCatching { EqualizerPreset.valueOf(presetName) }.getOrDefault(EqualizerPreset.NORMAL)
        val range = Pair(
            bundle.getInt("band_range_min", currentBandRange.first),
            bundle.getInt("band_range_max", currentBandRange.second)
        )
        val frequencies = bundle.getIntArray("band_frequencies")
        val levels = bundle.getFloatArray("band_levels")
        val bandCount = maxOf(
            frequencies?.size ?: 0,
            levels?.size ?: 0,
            bandSliders.size
        ).coerceAtLeast(1)

        if (bandSliders.size != bandCount || currentBandRange != range) {
            setupEqualizerBands(bandCount, range, frequencies, levels)
        } else if (levels != null) {
            applyBandLevels(levels.toList(), range)
        }

        isHydratingUi = true
        binding.equalizerSwitch.isChecked = enabled
        binding.presetSpinner.setSelection(EqualizerPreset.values().indexOf(preset).coerceAtLeast(0))
        binding.bassBoostSlider.progress = bundle.getInt("bass_boost", binding.bassBoostSlider.progress)
        binding.bassBoostValue.text = "${binding.bassBoostSlider.progress / 10}%"
        binding.virtualizerSlider.progress = bundle.getInt("virtualizer", binding.virtualizerSlider.progress)
        binding.virtualizerValue.text = "${binding.virtualizerSlider.progress / 10}%"
        isHydratingUi = false

        updateBandControlsEnabled(enabled)
        mirrorLiveStateToPrefs(enabled, preset, levels)
    }

    private fun loadPreviewForPreset(preset: EqualizerPreset) {
        val previewLevels = equalizerManager?.getPreviewBandLevels(preset).orEmpty()
        if (previewLevels.isNotEmpty()) {
            applyBandLevels(previewLevels, currentBandRange)
        }
    }

    private fun applyBandLevels(levels: List<Float>, range: Pair<Int, Int>) {
        currentBandRange = range
        bandSliders.forEachIndexed { index, slider ->
            val level = levels.getOrNull(index) ?: 0f
            val millibels = (level * 1000f).toInt().coerceIn(range.first, range.second)
            slider.progress = millibels - range.first
            bandLabels.getOrNull(index)?.text = "${String.format("%.1f", millibels / 1000f)} dB"
        }
    }

    private fun promotePresetSelectionToCustom() {
        if (binding.presetSpinner.selectedItemPosition == EqualizerPreset.CUSTOM.ordinal) {
            return
        }
        isHydratingUi = true
        binding.presetSpinner.setSelection(EqualizerPreset.CUSTOM.ordinal)
        isHydratingUi = false
        defaultPrefs.edit().putString("equalizer_preset", EqualizerPreset.CUSTOM.name).apply()
    }

    private fun markEqualizerEnabledLocally() {
        defaultPrefs.edit().putBoolean("equalizer_enabled", true).apply()
        if (binding.equalizerSwitch.isChecked) {
            return
        }
        isHydratingUi = true
        binding.equalizerSwitch.isChecked = true
        isHydratingUi = false
        updateBandControlsEnabled(true)
    }

    private fun persistCurrentCustomBandLevels() {
        val serialized = bandSliders.joinToString(",") { slider ->
            (slider.progress + currentBandRange.first).toString()
        }
        defaultPrefs.edit()
            .putString("equalizer_preset", EqualizerPreset.CUSTOM.name)
            .putString("custom_eq_bands", serialized)
            .apply()
    }

    private fun mirrorLiveStateToPrefs(enabled: Boolean, preset: EqualizerPreset, levels: FloatArray?) {
        val edit = defaultPrefs.edit()
            .putBoolean("equalizer_enabled", enabled)
            .putString("equalizer_preset", preset.name)
            .putInt("bass_boost_strength", binding.bassBoostSlider.progress)
            .putInt("virtualizer_strength", binding.virtualizerSlider.progress)
        if (preset == EqualizerPreset.CUSTOM && levels != null) {
            edit.putString(
                "custom_eq_bands",
                levels.joinToString(",") { level ->
                    (level * 1000f).toInt().coerceIn(currentBandRange.first, currentBandRange.second).toString()
                }
            )
        }
        edit.apply()
    }

    private fun sendCustomCommand(action: String, args: Bundle, refreshState: Boolean = false) {
        val controller = mediaController ?: return
        val future = controller.sendCustomCommand(SessionCommand(action, Bundle.EMPTY), args)
        if (!refreshState) return
        future.addListener({
            requestLiveEqualizerState()
        }, MoreExecutors.directExecutor())
    }

    private fun updateBandControlsEnabled(enabled: Boolean) {
        bandSliders.forEach { it.isEnabled = enabled }
        binding.bassBoostSlider.isEnabled = enabled
        binding.virtualizerSlider.isEnabled = enabled
        binding.presetSpinner.isEnabled = enabled
    }

    private fun formatFrequency(frequency: Int): String {
        return if (frequency < 1000) {
            "${frequency}Hz"
        } else {
            "${String.format("%.1f", frequency / 1000f)}kHz"
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        runCatching { mediaController?.release() }
        mediaController = null
        controllerFuture?.let { MediaController.releaseFuture(it) }
        controllerFuture = null
        equalizerManager?.release()
        _binding = null
        (activity as? AppCompatActivity)?.supportActionBar?.apply {
            setDisplayHomeAsUpEnabled(true)
            title = getString(com.stash.opusplayer.R.string.menu_settings)
        }
    }
}
