package com.stash.opusplayer.ui.appearance

import android.app.Dialog
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.*
import androidx.fragment.app.DialogFragment
import com.stash.opusplayer.R

class ColorPickerDialog : DialogFragment() {
    
    private var initialColor: Int = Color.BLACK
    private var onColorSelected: ((Int) -> Unit)? = null
    
    private lateinit var redSeekBar: SeekBar
    private lateinit var greenSeekBar: SeekBar
    private lateinit var blueSeekBar: SeekBar
    
    private lateinit var redValueText: TextView
    private lateinit var greenValueText: TextView
    private lateinit var blueValueText: TextView
    
    private lateinit var hexInput: EditText
    private lateinit var previewView: View
    private lateinit var recentsContainer: LinearLayout
    
    private var isUpdatingFromSeekBar = false
    private var isUpdatingFromHex = false
    
    companion object {
        private const val ARG_INITIAL_COLOR = "initial_color"
        
        fun newInstance(initialColor: Int, onColorSelected: (Int) -> Unit): ColorPickerDialog {
            return ColorPickerDialog().apply {
                arguments = Bundle().apply {
                    putInt(ARG_INITIAL_COLOR, initialColor)
                }
                this.onColorSelected = onColorSelected
            }
        }
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        initialColor = arguments?.getInt(ARG_INITIAL_COLOR) ?: Color.BLACK
        setStyle(STYLE_NORMAL, R.style.UpdateDialogTheme)
    }
    
    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        return createColorPickerView()
    }
    
    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val dialog = super.onCreateDialog(savedInstanceState)
        dialog.window?.setBackgroundDrawableResource(android.R.color.transparent)
        return dialog
    }
    
    private fun createColorPickerView(): View {
        val context = requireContext()
        val rootLayout = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 32, 32, 32)
            setBackgroundColor(Color.parseColor("#2D3748"))
        }
        
        // Title
        val title = TextView(context).apply {
            text = "Pick a Color"
            textSize = 20f
            setTextColor(Color.WHITE)
            setPadding(0, 0, 0, 24)
        }
        rootLayout.addView(title)
        
        // Preview
        previewView = View(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                (80 * resources.displayMetrics.density).toInt()
            ).apply {
                setMargins(0, 0, 0, 16)
            }
            setBackgroundColor(initialColor)
            
            // Add rounded corners
            background = GradientDrawable().apply {
                setColor(initialColor)
                cornerRadius = 12 * resources.displayMetrics.density
            }
        }
        rootLayout.addView(previewView)
        
        // Hex input
        val hexLabel = TextView(context).apply {
            text = "Hex Color"
            setTextColor(Color.parseColor("#CBD5E0"))
            textSize = 14f
        }
        rootLayout.addView(hexLabel)
        
        hexInput = EditText(context).apply {
            hint = "#RRGGBB"
            setText(ThemeManager.colorToHex(initialColor))
            setTextColor(Color.WHITE)
            setHintTextColor(Color.parseColor("#718096"))
            setPadding(16, 16, 16, 16)
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#4A5568"))
                cornerRadius = 8 * resources.displayMetrics.density
            }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins(0, 8, 0, 24)
            }
        }
        rootLayout.addView(hexInput)
        
        // RGB Sliders
        redSeekBar = createColorSlider(context, "Red", Color.red(initialColor))
        greenSeekBar = createColorSlider(context, "Green", Color.green(initialColor))
        blueSeekBar = createColorSlider(context, "Blue", Color.blue(initialColor))
        
        redValueText = TextView(context).apply {
            text = Color.red(initialColor).toString()
            setTextColor(Color.WHITE)
            textSize = 14f
        }
        greenValueText = TextView(context).apply {
            text = Color.green(initialColor).toString()
            setTextColor(Color.WHITE)
            textSize = 14f
        }
        blueValueText = TextView(context).apply {
            text = Color.blue(initialColor).toString()
            setTextColor(Color.WHITE)
            textSize = 14f
        }
        
        rootLayout.addView(createSliderRow(context, "Red", redSeekBar, redValueText))
        rootLayout.addView(createSliderRow(context, "Green", greenSeekBar, greenValueText))
        rootLayout.addView(createSliderRow(context, "Blue", blueSeekBar, blueValueText))
        
        // Recent colors
        val recentsLabel = TextView(context).apply {
            text = "Recent Colors"
            setTextColor(Color.parseColor("#CBD5E0"))
            textSize = 14f
            setPadding(0, 24, 0, 12)
        }
        rootLayout.addView(recentsLabel)
        
        recentsContainer = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }
        rootLayout.addView(recentsContainer)
        
        populateRecentColors()
        
        // Buttons
        val buttonsLayout = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins(0, 32, 0, 0)
            }
        }
        
        val cancelButton = Button(context).apply {
            text = "Cancel"
            setTextColor(Color.WHITE)
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#4A5568"))
                cornerRadius = 8 * resources.displayMetrics.density
            }
            layoutParams = LinearLayout.LayoutParams(
                0,
                LinearLayout.LayoutParams.WRAP_CONTENT,
                1f
            ).apply {
                setMargins(0, 0, 8, 0)
            }
            setOnClickListener { dismiss() }
        }
        
        val applyButton = Button(context).apply {
            text = "Apply"
            setTextColor(Color.WHITE)
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#EC407A"))
                cornerRadius = 8 * resources.displayMetrics.density
            }
            layoutParams = LinearLayout.LayoutParams(
                0,
                LinearLayout.LayoutParams.WRAP_CONTENT,
                1f
            ).apply {
                setMargins(8, 0, 0, 0)
            }
            setOnClickListener {
                val selectedColor = getCurrentColor()
                AppearancePreferences.persistRecentColor(requireContext(), selectedColor)
                onColorSelected?.invoke(selectedColor)
                dismiss()
            }
        }
        
        buttonsLayout.addView(cancelButton)
        buttonsLayout.addView(applyButton)
        rootLayout.addView(buttonsLayout)
        
        // Setup listeners
        setupListeners()
        
        return rootLayout
    }
    
    private fun createColorSlider(context: Context, label: String, initialValue: Int): SeekBar {
        return SeekBar(context).apply {
            max = 255
            progress = initialValue
            layoutParams = LinearLayout.LayoutParams(
                0,
                LinearLayout.LayoutParams.WRAP_CONTENT,
                1f
            )
        }
    }
    
    private fun createSliderRow(context: Context, label: String, seekBar: SeekBar, valueText: TextView): LinearLayout {
        return LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, 8, 0, 8)
            
            val labelText = TextView(context).apply {
                text = label
                setTextColor(Color.parseColor("#CBD5E0"))
                textSize = 14f
                layoutParams = LinearLayout.LayoutParams(
                    (60 * resources.displayMetrics.density).toInt(),
                    LinearLayout.LayoutParams.WRAP_CONTENT
                )
            }
            
            addView(labelText)
            addView(seekBar)
            
            valueText.layoutParams = LinearLayout.LayoutParams(
                (40 * resources.displayMetrics.density).toInt(),
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                setMargins(8, 0, 0, 0)
            }
            addView(valueText)
        }
    }
    
    private fun setupListeners() {
        // SeekBar listeners
        val seekBarListener = object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                if (fromUser && !isUpdatingFromHex) {
                    isUpdatingFromSeekBar = true
                    updateFromSeekBars()
                    isUpdatingFromSeekBar = false
                }
            }
            
            override fun onStartTrackingTouch(seekBar: SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: SeekBar?) {}
        }
        
        redSeekBar.setOnSeekBarChangeListener(seekBarListener)
        greenSeekBar.setOnSeekBarChangeListener(seekBarListener)
        blueSeekBar.setOnSeekBarChangeListener(seekBarListener)
        
        // Hex input listener
        hexInput.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            
            override fun afterTextChanged(s: Editable?) {
                if (!isUpdatingFromSeekBar) {
                    isUpdatingFromHex = true
                    updateFromHex()
                    isUpdatingFromHex = false
                }
            }
        })
    }
    
    private fun updateFromSeekBars() {
        val r = redSeekBar.progress
        val g = greenSeekBar.progress
        val b = blueSeekBar.progress
        
        redValueText.text = r.toString()
        greenValueText.text = g.toString()
        blueValueText.text = b.toString()
        
        val color = Color.rgb(r, g, b)
        updatePreview(color)
        
        // Update hex input
        hexInput.setText(ThemeManager.colorToHex(color))
    }
    
    private fun updateFromHex() {
        val hexText = hexInput.text.toString()
        try {
            val color = ThemeManager.hexToColor(hexText)
            
            redSeekBar.progress = Color.red(color)
            greenSeekBar.progress = Color.green(color)
            blueSeekBar.progress = Color.blue(color)
            
            redValueText.text = Color.red(color).toString()
            greenValueText.text = Color.green(color).toString()
            blueValueText.text = Color.blue(color).toString()
            
            updatePreview(color)
        } catch (e: Exception) {
            // Invalid hex, ignore
        }
    }
    
    private fun updatePreview(color: Int) {
        (previewView.background as? GradientDrawable)?.setColor(color)
    }
    
    private fun getCurrentColor(): Int {
        return Color.rgb(
            redSeekBar.progress,
            greenSeekBar.progress,
            blueSeekBar.progress
        )
    }
    
    private fun populateRecentColors() {
        val recentColors = AppearancePreferences.getRecentColors(requireContext())
        recentsContainer.removeAllViews()
        
        if (recentColors.isEmpty()) {
            val noRecentsText = TextView(requireContext()).apply {
                text = "No recent colors"
                setTextColor(Color.parseColor("#718096"))
                textSize = 12f
            }
            recentsContainer.addView(noRecentsText)
            return
        }
        
        recentColors.forEach { color ->
            val colorSwatch = View(requireContext()).apply {
                val size = (48 * resources.displayMetrics.density).toInt()
                layoutParams = LinearLayout.LayoutParams(size, size).apply {
                    setMargins(0, 0, 8, 0)
                }
                background = GradientDrawable().apply {
                    setColor(color)
                    cornerRadius = 8 * resources.displayMetrics.density
                    setStroke(2, Color.parseColor("#CBD5E0"))
                }
                setOnClickListener {
                    redSeekBar.progress = Color.red(color)
                    greenSeekBar.progress = Color.green(color)
                    blueSeekBar.progress = Color.blue(color)
                    updateFromSeekBars()
                }
            }
            recentsContainer.addView(colorSwatch)
        }
    }
}
