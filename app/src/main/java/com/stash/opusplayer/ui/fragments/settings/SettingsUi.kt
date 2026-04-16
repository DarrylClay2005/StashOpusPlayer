package com.stash.opusplayer.ui.fragments.settings

import android.content.Context
import android.text.InputType
import android.view.Gravity
import android.view.MenuItem
import android.view.View
import android.view.ViewGroup
import android.widget.ArrayAdapter
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Spinner
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.fragment.app.Fragment
import androidx.preference.PreferenceManager
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView
import com.google.android.material.slider.Slider
import com.google.android.material.switchmaterial.SwitchMaterial
import com.google.android.material.textfield.TextInputEditText
import com.google.android.material.textfield.TextInputLayout
import com.stash.opusplayer.R
import com.stash.opusplayer.ui.appearance.ThemeManager
import kotlin.math.roundToInt

internal fun Context.dp(value: Int): Int =
    ThemeManager.scaleDp(this, value)

internal fun Context.sp(value: Float): Float =
    ThemeManager.scaleSp(this, value)

internal fun Fragment.settingsPrefs() =
    requireContext().getSharedPreferences("settings", Context.MODE_PRIVATE)

internal fun Fragment.defaultPrefs() =
    PreferenceManager.getDefaultSharedPreferences(requireContext())

internal fun Fragment.createSettingsPage(
    title: String,
    subtitle: String
): Pair<ScrollView, LinearLayout> {
    val context = requireContext()
    val scrollView = ScrollView(context).apply {
        isFillViewport = true
        clipToPadding = false
    }
    val container = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(context.dp(16), context.dp(16), context.dp(16), context.dp(22))
    }
    scrollView.addView(
        container,
        ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
    )

    val heroCard = MaterialCardView(context).apply {
        radius = context.dp(22).toFloat()
        strokeWidth = context.dp(1)
        strokeColor = ContextCompat.getColor(context, R.color.accent_color)
        setCardBackgroundColor(ContextCompat.getColor(context, R.color.surface_variant))
        cardElevation = context.dp(2).toFloat()
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            bottomMargin = context.dp(14)
        }
    }

    val heroContent = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(context.dp(16), context.dp(16), context.dp(16), context.dp(16))
    }

    heroContent.addView(TextView(context).apply {
        text = title
        textSize = context.sp(26f)
        setTextColor(ContextCompat.getColor(context, R.color.text_primary))
        setTypeface(typeface, android.graphics.Typeface.BOLD)
    })

    heroContent.addView(TextView(context).apply {
        text = subtitle
        textSize = context.sp(14f)
        setTextColor(ContextCompat.getColor(context, R.color.text_secondary))
        setPadding(0, context.dp(10), 0, 0)
    })

    heroCard.addView(heroContent)
    container.addView(heroCard)
    return scrollView to container
}

internal fun Fragment.addSettingsSection(
    parent: LinearLayout,
    title: String,
    summary: String? = null
): LinearLayout {
    val context = requireContext()
    parent.addView(TextView(context).apply {
        text = title
        textSize = context.sp(18f)
        setTextColor(ContextCompat.getColor(context, R.color.text_primary))
        setTypeface(typeface, android.graphics.Typeface.BOLD)
        setPadding(0, context.dp(4), 0, context.dp(8))
    })

    if (!summary.isNullOrBlank()) {
        parent.addView(TextView(context).apply {
            text = summary
            textSize = context.sp(13f)
            setTextColor(ContextCompat.getColor(context, R.color.text_secondary))
            setPadding(0, 0, 0, context.dp(12))
        })
    }

    val card = MaterialCardView(context).apply {
        radius = context.dp(24).toFloat()
        strokeWidth = context.dp(1)
        strokeColor = ContextCompat.getColor(context, R.color.border_gray)
        setCardBackgroundColor(ContextCompat.getColor(context, R.color.surface_color))
        cardElevation = 0f
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            bottomMargin = context.dp(20)
        }
    }

    val content = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(context.dp(18), context.dp(18), context.dp(18), context.dp(18))
    }

    card.addView(content)
    parent.addView(card)
    return content
}

internal fun Fragment.addSettingsTile(
    parent: LinearLayout,
    title: String,
    summary: String,
    buttonLabel: String = "Open",
    onClick: () -> Unit
): MaterialCardView {
    val context = requireContext()
    val tile = MaterialCardView(context).apply {
        radius = context.dp(20).toFloat()
        strokeWidth = context.dp(1)
        strokeColor = ContextCompat.getColor(context, R.color.surface_variant)
        setCardBackgroundColor(ContextCompat.getColor(context, R.color.card_background))
        isClickable = true
        isFocusable = true
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            bottomMargin = context.dp(12)
        }
        setOnClickListener { onClick() }
    }

    val row = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(context.dp(18), context.dp(18), context.dp(18), context.dp(18))
    }

    val textColumn = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
    }

    textColumn.addView(TextView(context).apply {
        text = title
        textSize = context.sp(16f)
        setTextColor(ContextCompat.getColor(context, R.color.text_primary))
        setTypeface(typeface, android.graphics.Typeface.BOLD)
    })

    textColumn.addView(TextView(context).apply {
        text = summary
        textSize = context.sp(13f)
        setTextColor(ContextCompat.getColor(context, R.color.text_secondary))
        setPadding(0, context.dp(6), 0, 0)
    })

    row.addView(textColumn)
    row.addView(MaterialButton(context, null, com.google.android.material.R.attr.materialButtonOutlinedStyle).apply {
        text = buttonLabel
        textSize = context.sp(13f)
        minimumHeight = context.dp(40)
        setOnClickListener { onClick() }
    })

    tile.addView(row)
    parent.addView(tile)
    return tile
}

internal fun Fragment.addActionButton(
    parent: LinearLayout,
    label: String,
    outlined: Boolean = false,
    onClick: () -> Unit
): MaterialButton {
    val context = requireContext()
    val buttonStyle = if (outlined) {
        com.google.android.material.R.attr.materialButtonOutlinedStyle
    } else {
        com.google.android.material.R.attr.materialButtonStyle
    }
    return MaterialButton(context, null, buttonStyle).apply {
        text = label
        textSize = context.sp(14f)
        minimumHeight = context.dp(42)
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            bottomMargin = context.dp(10)
        }
        setOnClickListener { onClick() }
        parent.addView(this)
    }
}

internal fun Fragment.addHorizontalActions(parent: LinearLayout): LinearLayout {
    val context = requireContext()
    return LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            bottomMargin = context.dp(4)
        }
        parent.addView(this)
    }
}

internal fun Fragment.addSwitchControl(
    parent: LinearLayout,
    title: String,
    summary: String,
    checked: Boolean,
    onChanged: (Boolean) -> Unit
): SwitchMaterial {
    val context = requireContext()
    val row = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(0, 0, 0, context.dp(12))
    }
    val toggle = SwitchMaterial(context).apply {
        text = title
        isChecked = checked
        textSize = context.sp(15f)
        setTextColor(ContextCompat.getColor(context, R.color.text_primary))
    }
    row.addView(toggle)
    row.addView(TextView(context).apply {
        text = summary
        textSize = context.sp(12f)
        setTextColor(ContextCompat.getColor(context, R.color.text_secondary))
        setPadding(0, context.dp(4), 0, 0)
    })
    parent.addView(row)
    toggle.setOnCheckedChangeListener { _, isChecked -> onChanged(isChecked) }
    return toggle
}

internal fun Fragment.addSliderControl(
    parent: LinearLayout,
    title: String,
    summary: String,
    valueFrom: Float,
    valueTo: Float,
    stepSize: Float,
    initialValue: Float,
    formatter: (Float) -> String,
    onChanged: (Float, Boolean) -> Unit
): Pair<Slider, TextView> {
    val context = requireContext()
    val row = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(0, 0, 0, context.dp(16))
    }

    row.addView(TextView(context).apply {
        text = title
        textSize = context.sp(15f)
        setTextColor(ContextCompat.getColor(context, R.color.text_primary))
        setTypeface(typeface, android.graphics.Typeface.BOLD)
    })

    row.addView(TextView(context).apply {
        text = summary
        textSize = context.sp(12f)
        setTextColor(ContextCompat.getColor(context, R.color.text_secondary))
        setPadding(0, context.dp(4), 0, context.dp(8))
    })

    val valueView = TextView(context).apply {
        text = formatter(initialValue)
        textSize = context.sp(12f)
        setTextColor(ContextCompat.getColor(context, R.color.text_accent))
        setPadding(0, 0, 0, context.dp(6))
    }
    row.addView(valueView)

    val slider = Slider(context).apply {
        this.valueFrom = valueFrom
        this.valueTo = valueTo
        this.stepSize = stepSize
        value = initialValue.coerceIn(valueFrom, valueTo)
        addOnChangeListener { _, value, fromUser ->
            valueView.text = formatter(value)
            onChanged(value, fromUser)
        }
    }
    row.addView(slider)
    parent.addView(row)
    return slider to valueView
}

internal fun Fragment.addSpinnerControl(
    parent: LinearLayout,
    title: String,
    summary: String,
    entries: List<String>
): Spinner {
    val context = requireContext()
    val row = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(0, 0, 0, context.dp(14))
    }

    row.addView(TextView(context).apply {
        text = title
        textSize = context.sp(15f)
        setTextColor(ContextCompat.getColor(context, R.color.text_primary))
        setTypeface(typeface, android.graphics.Typeface.BOLD)
    })

    row.addView(TextView(context).apply {
        text = summary
        textSize = context.sp(12f)
        setTextColor(ContextCompat.getColor(context, R.color.text_secondary))
        setPadding(0, context.dp(4), 0, context.dp(8))
    })

    val spinner = Spinner(context).apply {
        adapter = ArrayAdapter(
            context,
            android.R.layout.simple_spinner_item,
            entries
        ).also { it.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item) }
    }
    row.addView(spinner)
    parent.addView(row)
    return spinner
}

internal fun Fragment.addTextInputControl(
    parent: LinearLayout,
    title: String,
    summary: String,
    hint: String,
    initialText: String,
    inputType: Int = InputType.TYPE_CLASS_TEXT
): TextInputEditText {
    val context = requireContext()
    val row = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(0, 0, 0, context.dp(14))
    }

    row.addView(TextView(context).apply {
        text = title
        textSize = context.sp(15f)
        setTextColor(ContextCompat.getColor(context, R.color.text_primary))
        setTypeface(typeface, android.graphics.Typeface.BOLD)
    })

    row.addView(TextView(context).apply {
        text = summary
        textSize = context.sp(12f)
        setTextColor(ContextCompat.getColor(context, R.color.text_secondary))
        setPadding(0, context.dp(4), 0, context.dp(8))
    })

    val inputLayout = TextInputLayout(context).apply {
        this.hint = hint
        boxBackgroundMode = TextInputLayout.BOX_BACKGROUND_OUTLINE
    }
    val editText = TextInputEditText(context).apply {
        setText(initialText)
        this.inputType = inputType
    }
    inputLayout.addView(editText)
    row.addView(inputLayout)
    parent.addView(row)
    return editText
}

internal fun Fragment.addBodyText(
    parent: LinearLayout,
    text: String
): TextView {
    val context = requireContext()
    return TextView(context).apply {
        this.text = text
        textSize = context.sp(12f)
        setTextColor(ContextCompat.getColor(context, R.color.text_secondary))
        setPadding(0, 0, 0, context.dp(12))
        parent.addView(this)
    }
}

internal fun Fragment.addChipButtonRow(
    parent: LinearLayout,
    buttons: List<Pair<String, () -> Unit>>
): HorizontalScrollView {
    val context = requireContext()
    val scroll = HorizontalScrollView(context).apply {
        isHorizontalScrollBarEnabled = false
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            bottomMargin = context.dp(16)
        }
    }
    val row = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
    }
    buttons.forEachIndexed { index, (label, onClick) ->
        row.addView(MaterialButton(
            context,
            null,
            com.google.android.material.R.attr.materialButtonOutlinedStyle
        ).apply {
            text = label
            textSize = context.sp(13f)
            minimumHeight = context.dp(38)
            setOnClickListener { onClick() }
            if (layoutParams is ViewGroup.MarginLayoutParams) {
                (layoutParams as ViewGroup.MarginLayoutParams).marginEnd = context.dp(8)
            }
            setPadding(context.dp(12), 0, context.dp(12), 0)
            if (index < buttons.lastIndex) {
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply {
                    marginEnd = context.dp(8)
                }
            }
        })
    }
    scroll.addView(row)
    parent.addView(scroll)
    return scroll
}

internal fun Fragment.navigateToSettingsScreen(fragment: Fragment) {
    parentFragmentManager.beginTransaction()
        .replace(R.id.main_content, fragment)
        .addToBackStack(fragment::class.java.simpleName)
        .commit()
}

internal fun Fragment.updateSettingsActionBar(
    title: String,
    showBackButton: Boolean
) {
    val host = activity as? AppCompatActivity ?: return
    host.supportActionBar?.apply {
        this.title = title
        setDisplayHomeAsUpEnabled(showBackButton)
        setDisplayShowHomeEnabled(showBackButton)
    }
}

abstract class NavigableSettingsFragment : Fragment() {
    protected abstract val screenTitle: String

    override fun onResume() {
        super.onResume()
        updateSettingsActionBar(screenTitle, true)
    }

    @Suppress("DEPRECATION")
    override fun onViewCreated(view: View, savedInstanceState: android.os.Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        setHasOptionsMenu(true)
        updateSettingsActionBar(screenTitle, true)
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return if (item.itemId == android.R.id.home) {
            if (parentFragmentManager.backStackEntryCount > 0) {
                parentFragmentManager.popBackStack()
            } else {
                parentFragmentManager.beginTransaction()
                    .replace(R.id.main_content, com.stash.opusplayer.ui.fragments.SettingsFragment())
                    .commit()
            }
            true
        } else {
            super.onOptionsItemSelected(item)
        }
    }
}
