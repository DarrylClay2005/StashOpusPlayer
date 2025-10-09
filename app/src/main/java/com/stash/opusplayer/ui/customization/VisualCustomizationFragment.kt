package com.stash.opusplayer.ui.customization

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.provider.MediaStore
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.*
import androidx.activity.result.contract.ActivityResultContracts
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import com.stash.opusplayer.R
import com.stash.opusplayer.ui.appearance.VisualCustomizationManager
import kotlinx.coroutines.launch

/**
 * Fragment for visual customization settings including photo backgrounds
 */
class VisualCustomizationFragment : Fragment() {

    companion object {
        private const val TAG = "VisualCustomizationFragment"
        private const val REQUEST_IMAGE_PICK = 1001
    }

    // UI Components
    private lateinit var backgroundTypeSpinner: Spinner
    private lateinit var photoBackgroundContainer: LinearLayout
    private lateinit var photoPreview: ImageView
    private lateinit var selectPhotoButton: Button
    private lateinit var effectsContainer: LinearLayout
    private lateinit var blurSeekBar: SeekBar
    private lateinit var tintSeekBar: SeekBar
    private lateinit var dimSeekBar: SeekBar
    private lateinit var parallaxSwitch: Switch
    private lateinit var breathingSwitch: Switch
    private lateinit var colorShiftSwitch: Switch
    private lateinit var applyButton: Button
    private lateinit var resetButton: Button
    private lateinit var previewBackground: View
    
    // Customization Manager
    private lateinit var customizationManager: VisualCustomizationManager
    
    // Image picker launcher
    private val imagePickerLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            result.data?.data?.let { uri ->
                lifecycleScope.launch {
                    val success = customizationManager.setPhotoBackground(uri)
                    if (success) {
                        Toast.makeText(requireContext(), "Photo background set successfully", Toast.LENGTH_SHORT).show()
                        updatePreview()
                    } else {
                        Toast.makeText(requireContext(), "Failed to load image", Toast.LENGTH_SHORT).show()
                    }
                }
            }
        }
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        return inflater.inflate(R.layout.fragment_visual_customization, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        
        customizationManager = VisualCustomizationManager(requireContext())
        
        initializeViews(view)
        setupListeners()
        loadCurrentSettings()
    }
    
    private fun initializeViews(view: View) {
        // Background type selection
        backgroundTypeSpinner = view.findViewById(R.id.background_type_spinner)
        setupBackgroundTypeSpinner()
        
        // Photo background components
        photoBackgroundContainer = view.findViewById(R.id.photo_background_container)
        photoPreview = view.findViewById(R.id.photo_preview)
        selectPhotoButton = view.findViewById(R.id.select_photo_button)
        
        // Effect controls
        effectsContainer = view.findViewById(R.id.effects_container)
        blurSeekBar = view.findViewById(R.id.blur_seekbar)
        tintSeekBar = view.findViewById(R.id.tint_seekbar)
        dimSeekBar = view.findViewById(R.id.dim_seekbar)
        
        // Animation switches
        parallaxSwitch = view.findViewById(R.id.parallax_switch)
        breathingSwitch = view.findViewById(R.id.breathing_switch)
        colorShiftSwitch = view.findViewById(R.id.color_shift_switch)
        
        // Action buttons
        applyButton = view.findViewById(R.id.apply_button)
        resetButton = view.findViewById(R.id.reset_button)
        previewBackground = view.findViewById(R.id.preview_background)
        
        // Setup seekbar ranges
        blurSeekBar.max = 100
        tintSeekBar.max = 100
        dimSeekBar.max = 100
    }
    
    private fun setupBackgroundTypeSpinner() {
        val backgroundTypes = arrayOf("Gradient", "Solid Color", "Photo Background")
        val adapter = ArrayAdapter(requireContext(), android.R.layout.simple_spinner_item, backgroundTypes)
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        backgroundTypeSpinner.adapter = adapter
    }
    
    private fun setupListeners() {
        // Background type selection
        backgroundTypeSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                when (position) {
                    0 -> {
                        customizationManager.setBackgroundType(VisualCustomizationManager.BACKGROUND_TYPE_GRADIENT)
                        showPhotoControls(false)
                    }
                    1 -> {
                        customizationManager.setBackgroundType(VisualCustomizationManager.BACKGROUND_TYPE_COLOR)
                        showPhotoControls(false)
                    }
                    2 -> {
                        customizationManager.setBackgroundType(VisualCustomizationManager.BACKGROUND_TYPE_PHOTO)
                        showPhotoControls(true)
                    }
                }
                updatePreview()
            }
            
            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }
        
        // Photo selection
        selectPhotoButton.setOnClickListener {
            openImagePicker()
        }
        
        // Effect controls
        blurSeekBar.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                if (fromUser) {
                    customizationManager.updatePhotoSettings(
                        blurRadius = progress,
                        dimming = customizationManager.getPhotoDimming(),
                        opacity = customizationManager.getPhotoOpacity()
                    )
                    updatePreview()
                }
            }
            override fun onStartTrackingTouch(seekBar: SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: SeekBar?) {}
        })
        
        tintSeekBar.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                if (fromUser) {
                    customizationManager.updatePhotoSettings(
                        blurRadius = customizationManager.getPhotoBlurRadius(),
                        tintIntensity = progress,
                        tintColor = Color.parseColor("#6A1B9A")
                    )
                    updatePreview()
                }
            }
            override fun onStartTrackingTouch(seekBar: SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: SeekBar?) {}
        })
        
        dimSeekBar.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                if (fromUser) {
                    customizationManager.updatePhotoSettings(
                        blurRadius = customizationManager.getPhotoBlurRadius(),
                        dimming = progress,
                        opacity = customizationManager.getPhotoOpacity()
                    )
                    updatePreview()
                }
            }
            override fun onStartTrackingTouch(seekBar: SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: SeekBar?) {}
        })
        
        // Animation switches
        parallaxSwitch.setOnCheckedChangeListener { _, isChecked ->
            customizationManager.setParallaxEnabled(isChecked)
        }
        
        breathingSwitch.setOnCheckedChangeListener { _, isChecked ->
            customizationManager.setBreathingEnabled(isChecked)
        }
        
        colorShiftSwitch.setOnCheckedChangeListener { _, isChecked ->
            customizationManager.setColorShiftEnabled(isChecked)
        }
        
        // Action buttons
        applyButton.setOnClickListener {
            applyCustomization()
        }
        
        resetButton.setOnClickListener {
            resetToDefaults()
        }
    }
    
    private fun loadCurrentSettings() {
        // Load background type
        val backgroundType = customizationManager.getBackgroundType()
        backgroundTypeSpinner.setSelection(when (backgroundType) {
            VisualCustomizationManager.BACKGROUND_TYPE_GRADIENT -> 0
            VisualCustomizationManager.BACKGROUND_TYPE_COLOR -> 1
            VisualCustomizationManager.BACKGROUND_TYPE_PHOTO -> 2
            else -> 0
        })
        
        // Show photo controls if photo background is selected
        showPhotoControls(backgroundType == VisualCustomizationManager.BACKGROUND_TYPE_PHOTO)
        
        // Load effect settings
        blurSeekBar.progress = customizationManager.getPhotoBlurRadius()
        tintSeekBar.progress = customizationManager.getPhotoTintIntensity()
        dimSeekBar.progress = customizationManager.getPhotoDimming()
        
        // Load animation settings
        parallaxSwitch.isChecked = customizationManager.isParallaxEnabled()
        breathingSwitch.isChecked = customizationManager.isBreathingEnabled()
        colorShiftSwitch.isChecked = customizationManager.isColorShiftEnabled()
        
        // Update preview
        updatePreview()
    }
    
    private fun showPhotoControls(show: Boolean) {
        val visibility = if (show) View.VISIBLE else View.GONE
        photoBackgroundContainer.visibility = visibility
        effectsContainer.visibility = visibility
    }
    
    private fun openImagePicker() {
        val intent = Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI).apply {
            type = "image/*"
        }
        imagePickerLauncher.launch(intent)
    }
    
    
    private fun updatePreview() {
        // Update the preview with current background settings
        previewBackground.background = customizationManager.getCurrentBackground()
    }
    
    private fun applyCustomization() {
        // Settings are already applied when changed
        Toast.makeText(requireContext(), "Visual customization applied", Toast.LENGTH_SHORT).show()
        requireActivity().recreate() // Recreate activity to apply changes fully
    }
    
    private fun resetToDefaults() {
        // Reset photo settings to defaults
        customizationManager.updatePhotoSettings()
        
        // Clear any photo background
        customizationManager.clearPhotoBackground()
        
        // Default to gradient
        customizationManager.setBackgroundType(VisualCustomizationManager.BACKGROUND_TYPE_GRADIENT)
        
        loadCurrentSettings()
        Toast.makeText(requireContext(), "Settings reset to defaults", Toast.LENGTH_SHORT).show()
    }
}