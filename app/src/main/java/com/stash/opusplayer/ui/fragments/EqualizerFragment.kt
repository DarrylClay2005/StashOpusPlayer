package com.stash.opusplayer.ui.fragments

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.*
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import com.stash.opusplayer.audio.EqualizerManager
import com.stash.opusplayer.audio.EqualizerPreset
import com.stash.opusplayer.databinding.FragmentEqualizerBinding
import kotlinx.coroutines.launch

class EqualizerFragment : Fragment() {
    
    private var _binding: FragmentEqualizerBinding? = null
    private val binding get() = _binding!!
    
    private var equalizerManager: EqualizerManager? = null
    private val bandSliders = mutableListOf<SeekBar>()
    private val bandLabels = mutableListOf<TextView>()
    
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
        
        initializeEqualizer()
        setupUI()
        setupListeners()
    }
    
    private fun initializeEqualizer() {
        equalizerManager = EqualizerManager(requireContext())
        // Initialize with a dummy audio session ID for now
        // In a real implementation, this would be connected to the actual player
        equalizerManager?.initialize(0)
    }
    
    private fun setupUI() {
        setupPresetSpinner()
        setupEqualizerBands()
        setupEffectsControls()
        updateUIFromEqualizer()
    }
    
    private fun setupPresetSpinner() {
        val presets = EqualizerPreset.values().map { it.name.replace("_", " ").lowercase().replaceFirstChar { char -> char.uppercaseChar() } }
        val adapter = ArrayAdapter(requireContext(), android.R.layout.simple_spinner_item, presets)
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        binding.presetSpinner.adapter = adapter
    }
    
    private fun setupEqualizerBands() {
        val numberOfBands = equalizerManager?.getNumberOfBands() ?: 5
        val bandRange = equalizerManager?.getBandRange() ?: Pair(-1500, 1500)
        
        // Clear existing views
        binding.bandsContainer.removeAllViews()
        bandSliders.clear()
        bandLabels.clear()
        
        for (i in 0 until numberOfBands) {
            val bandView = createBandView(i, bandRange)
            binding.bandsContainer.addView(bandView)
        }
    }
    
    private fun createBandView(bandIndex: Int, range: Pair<Int, Int>): View {
        val bandLayout = LinearLayout(requireContext()).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                0,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                1f
            ).apply {
                setMargins(8, 0, 8, 0)
            }
        }
        
        // Frequency label
        val frequency = equalizerManager?.getBandFrequency(bandIndex) ?: 0
        val frequencyLabel = TextView(requireContext()).apply {
            text = formatFrequency(frequency)
            textSize = 12f
            gravity = android.view.Gravity.CENTER
        }
        
        // Level label
        val levelLabel = TextView(requireContext()).apply {
            text = "0 dB"
            textSize = 10f
            gravity = android.view.Gravity.CENTER
        }
        
        // Band slider (vertical)
        val bandSlider = SeekBar(requireContext()).apply {
            max = range.second - range.first
            progress = -range.first  // Center position
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                200
            )
            
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                    if (fromUser) {
                        val level = (progress + range.first).toFloat() / 1000f
                        equalizerManager?.setBandLevel(bandIndex, level)
                        levelLabel.text = "${String.format("%.1f", level)} dB"
                    }
                }
                override fun onStartTrackingTouch(seekBar: SeekBar?) {}
                override fun onStopTrackingTouch(seekBar: SeekBar?) {}
            })
        }
        
        bandSliders.add(bandSlider)
        bandLabels.add(levelLabel)
        
        bandLayout.addView(frequencyLabel)
        bandLayout.addView(bandSlider)
        bandLayout.addView(levelLabel)
        
        return bandLayout
    }
    
    private fun setupEffectsControls() {
        // Bass Boost
        binding.bassBoostSlider.max = 1000
        binding.bassBoostSlider.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                if (fromUser) {
                    equalizerManager?.setBassBoost(progress)
                    binding.bassBoostValue.text = "${progress / 10}%"
                }
            }
            override fun onStartTrackingTouch(seekBar: SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: SeekBar?) {}
        })
        
        // Virtualizer
        binding.virtualizerSlider.max = 1000
        binding.virtualizerSlider.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                if (fromUser) {
                    equalizerManager?.setVirtualizer(progress)
                    binding.virtualizerValue.text = "${progress / 10}%"
                }
            }
            override fun onStartTrackingTouch(seekBar: SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: SeekBar?) {}
        })
    }
    
    private fun setupListeners() {
        binding.equalizerSwitch.setOnCheckedChangeListener { _, isChecked ->
            equalizerManager?.setEnabled(isChecked)
            updateBandControlsEnabled(isChecked)
        }
        
        binding.presetSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                val preset = EqualizerPreset.values()[position]
                equalizerManager?.setPreset(preset)
                updateBandSlidersFromEqualizer()
            }
            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }
    }
    
    private fun updateUIFromEqualizer() {
        lifecycleScope.launch {
            equalizerManager?.let { eq ->
                eq.isEnabled.collect { enabled ->
                    binding.equalizerSwitch.isChecked = enabled
                    updateBandControlsEnabled(enabled)
                }
            }
        }
        
        lifecycleScope.launch {
            equalizerManager?.let { eq ->
                eq.currentPreset.collect { preset ->
                    binding.presetSpinner.setSelection(preset.ordinal)
                }
            }
        }
        
        lifecycleScope.launch {
            equalizerManager?.let { eq ->
                eq.bassBoostLevel.collect { level ->
                    binding.bassBoostSlider.progress = level
                    binding.bassBoostValue.text = "${level / 10}%"
                }
            }
        }
        
        lifecycleScope.launch {
            equalizerManager?.let { eq ->
                eq.virtualizerLevel.collect { level ->
                    binding.virtualizerSlider.progress = level
                    binding.virtualizerValue.text = "${level / 10}%"
                }
            }
        }
    }
    
    private fun updateBandSlidersFromEqualizer() {
        lifecycleScope.launch {
            equalizerManager?.bandLevels?.collect { levels ->
                levels.forEachIndexed { index, level ->
                    if (index < bandSliders.size) {
                        val range = equalizerManager?.getBandRange() ?: Pair(-1500, 1500)
                        val progress = (level * 1000).toInt() - range.first
                        bandSliders[index].progress = progress
                        bandLabels[index].text = "${String.format("%.1f", level)} dB"
                    }
                }
            }
        }
    }
    
    private fun updateBandControlsEnabled(enabled: Boolean) {
        bandSliders.forEach { it.isEnabled = enabled }
        binding.bassBoostSlider.isEnabled = enabled
        binding.virtualizerSlider.isEnabled = enabled
        binding.presetSpinner.isEnabled = enabled
    }
    
    private fun formatFrequency(frequency: Int): String {
        return when {
            frequency < 1000 -> "${frequency}Hz"
            else -> "${String.format("%.1f", frequency / 1000f)}kHz"
        }
    }
    
    override fun onDestroyView() {
        super.onDestroyView()
        equalizerManager?.release()
        _binding = null
    }
}
