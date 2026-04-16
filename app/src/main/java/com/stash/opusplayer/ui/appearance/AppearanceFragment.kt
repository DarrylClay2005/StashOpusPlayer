package com.stash.opusplayer.ui.appearance

import android.graphics.Color
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.AdapterView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import com.stash.opusplayer.ui.fragments.settings.NavigableSettingsFragment
import com.stash.opusplayer.ui.fragments.settings.addActionButton
import com.stash.opusplayer.ui.fragments.settings.addBodyText
import com.stash.opusplayer.ui.fragments.settings.addChipButtonRow
import com.stash.opusplayer.ui.fragments.settings.addSettingsSection
import com.stash.opusplayer.ui.fragments.settings.addSliderControl
import com.stash.opusplayer.ui.fragments.settings.addSpinnerControl
import com.stash.opusplayer.ui.fragments.settings.addSwitchControl
import com.stash.opusplayer.ui.fragments.settings.createSettingsPage
import com.stash.opusplayer.ui.managers.MiniPlayerToggleManager
import kotlin.math.roundToInt

class AppearanceFragment : NavigableSettingsFragment() {

    override val screenTitle: String = "Appearance"

    private data class AppearancePalette(
        val label: String,
        val primaryColor: Int,
        val accentColor: Int,
        val backgroundColor: Int,
        val textPrimaryColor: Int,
        val textSecondaryColor: Int
    )

    private val palettes = listOf(
        AppearancePalette(
            label = "Nightwave",
            primaryColor = Color.parseColor("#1A2335"),
            accentColor = Color.parseColor("#F97316"),
            backgroundColor = Color.parseColor("#0A1220"),
            textPrimaryColor = Color.parseColor("#F8FAFC"),
            textSecondaryColor = Color.parseColor("#CBD5E1")
        ),
        AppearancePalette(
            label = "Vinyl Ember",
            primaryColor = Color.parseColor("#2B1D17"),
            accentColor = Color.parseColor("#FB923C"),
            backgroundColor = Color.parseColor("#120D0B"),
            textPrimaryColor = Color.parseColor("#FFF7ED"),
            textSecondaryColor = Color.parseColor("#E7C9B3")
        ),
        AppearancePalette(
            label = "Glass Blue",
            primaryColor = Color.parseColor("#18324E"),
            accentColor = Color.parseColor("#38BDF8"),
            backgroundColor = Color.parseColor("#0B1726"),
            textPrimaryColor = Color.parseColor("#E0F2FE"),
            textSecondaryColor = Color.parseColor("#BAE6FD")
        ),
        AppearancePalette(
            label = "Forest Mix",
            primaryColor = Color.parseColor("#173126"),
            accentColor = Color.parseColor("#34D399"),
            backgroundColor = Color.parseColor("#0A1712"),
            textPrimaryColor = Color.parseColor("#ECFDF5"),
            textSecondaryColor = Color.parseColor("#A7F3D0")
        )
    )

    private lateinit var miniPlayerToggleManager: MiniPlayerToggleManager
    private lateinit var setupSummaryView: TextView
    private lateinit var densitySummaryView: TextView

    private var currentPrefs = AppearancePreferences()
    private var hydratingNowPlayingTheme = false
    private var hydratingMiniPlayerStyle = false

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        currentPrefs = AppearancePreferences.fromPrefs(requireContext())
        miniPlayerToggleManager = MiniPlayerToggleManager(requireContext())

        val (scrollView, content) = createSettingsPage(
            title = "Appearance",
            subtitle = "This screen was rebuilt around stable controls only: tighter sizing, dependable player layouts, and curated palettes instead of the old crash-prone customization stack."
        )

        buildCurrentSetup(content)
        buildPaletteSection(content)
        buildPlayerLayoutSection(content)
        buildSizingSection(content)
        buildResetSection(content)
        refreshSummary()

        return scrollView
    }

    private fun buildCurrentSetup(parent: LinearLayout) {
        val section = addSettingsSection(
            parent,
            "Current Setup",
            "These values apply live across the library, mini player, and now playing screen."
        )

        setupSummaryView = addBodyText(section, "")
        densitySummaryView = addBodyText(section, "")

        addActionButton(section, "Refresh appearance now", outlined = true) {
            currentPrefs = AppearancePreferences.fromPrefs(requireContext())
            refreshSummary()
            ThemeManager.broadcastChange(requireContext(), false)
        }
    }

    private fun buildPaletteSection(parent: LinearLayout) {
        val section = addSettingsSection(
            parent,
            "Color Direction",
            "Only stable presets live here now. That keeps the appearance screen fast and avoids broken edge cases from the old custom picker flow."
        )

        addChipButtonRow(
            section,
            palettes.map { palette ->
                palette.label to {
                    persistAppearance(
                        currentPrefs.copy(
                            primaryColor = palette.primaryColor,
                            accentColor = palette.accentColor,
                            backgroundColor = palette.backgroundColor,
                            textPrimaryColor = palette.textPrimaryColor,
                            textSecondaryColor = palette.textSecondaryColor
                        )
                    )
                    Toast.makeText(requireContext(), "${palette.label} applied.", Toast.LENGTH_SHORT).show()
                }
            }
        )

        addSwitchControl(
            section,
            title = "Bold headers",
            summary = "Makes toolbar and section titles read a little stronger across the rebuilt layouts.",
            checked = currentPrefs.titleBold
        ) { enabled ->
            persistAppearance(currentPrefs.copy(titleBold = enabled))
        }

        addSwitchControl(
            section,
            title = "Card shadows",
            summary = "Keeps elevation cues on cards without bringing back the heavy old effects stack.",
            checked = currentPrefs.shadowsEnabled
        ) { enabled ->
            persistAppearance(currentPrefs.copy(shadowsEnabled = enabled))
        }
    }

    private fun buildPlayerLayoutSection(parent: LinearLayout) {
        val section = addSettingsSection(
            parent,
            "Player Layouts",
            "These are the rebuilt controls that drive the now playing screen and the mini player without the old dead toggles."
        )

        val nowPlayingThemes = NowPlayingLayoutTheme.entries
        val nowPlayingSpinner = addSpinnerControl(
            section,
            title = "Now playing layout",
            summary = "Aurora stays balanced, Vinyl Deck leans into artwork, and Minimal Deck keeps playback tighter.",
            entries = nowPlayingThemes.map { it.displayName }
        )
        nowPlayingSpinner.setSelection(nowPlayingThemes.indexOf(currentPrefs.nowPlayingLayoutTheme).coerceAtLeast(0))
        nowPlayingSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                if (!hydratingNowPlayingTheme) {
                    hydratingNowPlayingTheme = true
                    return
                }
                val selected = nowPlayingThemes[position]
                if (selected != currentPrefs.nowPlayingLayoutTheme) {
                    persistAppearance(currentPrefs.copy(nowPlayingLayoutTheme = selected))
                }
            }

            override fun onNothingSelected(parent: AdapterView<*>?) = Unit
        }

        val miniPlayerStyles = miniPlayerToggleManager.getAvailableStyles()
        val miniPlayerSpinner = addSpinnerControl(
            section,
            title = "Mini player style",
            summary = "Each option now routes to a maintained mini player surface instead of the old experimental toggle mess.",
            entries = miniPlayerStyles.map { it.second }
        )
        miniPlayerSpinner.setSelection(
            miniPlayerStyles.indexOfFirst { it.first == miniPlayerToggleManager.getMiniPlayerStyle() }.coerceAtLeast(0)
        )
        miniPlayerSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                if (!hydratingMiniPlayerStyle) {
                    hydratingMiniPlayerStyle = true
                    return
                }
                val selectedStyle = miniPlayerStyles[position].first
                if (selectedStyle != miniPlayerToggleManager.getMiniPlayerStyle()) {
                    miniPlayerToggleManager.setMiniPlayerStyle(selectedStyle)
                    ThemeManager.broadcastChange(requireContext(), false)
                    refreshSummary()
                }
            }

            override fun onNothingSelected(parent: AdapterView<*>?) = Unit
        }

        addSwitchControl(
            section,
            title = "Show album art in mini player",
            summary = "Keeps the artwork tile visible inside the mini player.",
            checked = currentPrefs.miniPlayerShowArt
        ) { enabled ->
            persistAppearance(currentPrefs.copy(miniPlayerShowArt = enabled))
        }

        addSwitchControl(
            section,
            title = "Show artist in mini player",
            summary = "Keeps the second text line visible when you want more context in the collapsed player.",
            checked = currentPrefs.miniPlayerShowArtist
        ) { enabled ->
            persistAppearance(currentPrefs.copy(miniPlayerShowArtist = enabled))
        }

        addSwitchControl(
            section,
            title = "Compact mini player spacing",
            summary = "Shrinks padding and line count so the mini player sits tighter against the rest of the app.",
            checked = currentPrefs.miniPlayerCompactMode
        ) { enabled ->
            persistAppearance(currentPrefs.copy(miniPlayerCompactMode = enabled))
        }

        addSwitchControl(
            section,
            title = "Spin mini player artwork",
            summary = "Only affects the rotating artwork effect when music is actually playing.",
            checked = currentPrefs.miniPlayerSpinningArt
        ) { enabled ->
            persistAppearance(currentPrefs.copy(miniPlayerSpinningArt = enabled))
        }
    }

    private fun buildSizingSection(parent: LinearLayout) {
        val section = addSettingsSection(
            parent,
            "Sizing & Density",
            "These controls replace the old broken element sizing code with a smaller, safer range."
        )

        addSliderControl(
            section,
            title = "Control size",
            summary = "Scales icon buttons and action buttons across the app.",
            valueFrom = 0.78f,
            valueTo = 1.0f,
            stepSize = 0.02f,
            initialValue = currentPrefs.buttonSizeScale,
            formatter = { "${(it * 100).roundToInt()}%" }
        ) { value, fromUser ->
            if (fromUser) {
                persistAppearance(currentPrefs.copy(buttonSizeScale = value))
            }
        }

        addSliderControl(
            section,
            title = "Text scale",
            summary = "Adjusts the text sizing used by rebuilt screens without stepping outside a sane range.",
            valueFrom = 0.9f,
            valueTo = 1.15f,
            stepSize = 0.05f,
            initialValue = currentPrefs.fontScale,
            formatter = { "${(it * 100).roundToInt()}%" }
        ) { value, fromUser ->
            if (fromUser) {
                persistAppearance(currentPrefs.copy(fontScale = value))
            }
        }

        addSliderControl(
            section,
            title = "Mini player height",
            summary = "Caps the collapsed player to a tighter range so it no longer feels oversized.",
            valueFrom = 56f,
            valueTo = 72f,
            stepSize = 2f,
            initialValue = currentPrefs.miniPlayerHeightDp.toFloat(),
            formatter = { "${it.roundToInt()} dp" }
        ) { value, fromUser ->
            if (fromUser) {
                persistAppearance(currentPrefs.copy(miniPlayerHeightDp = value.roundToInt()))
            }
        }

        addSliderControl(
            section,
            title = "Card corner radius",
            summary = "Changes the roundness of the rebuilt cards without touching the underlying layout logic.",
            valueFrom = 12f,
            valueTo = 28f,
            stepSize = 2f,
            initialValue = currentPrefs.cardCornerRadiusDp.toFloat(),
            formatter = { "${it.roundToInt()} dp" }
        ) { value, fromUser ->
            if (fromUser) {
                persistAppearance(currentPrefs.copy(cardCornerRadiusDp = value.roundToInt()))
            }
        }
    }

    private fun buildResetSection(parent: LinearLayout) {
        val section = addSettingsSection(
            parent,
            "Recovery",
            "Use these when old appearance values left the app feeling oversized or visually inconsistent."
        )

        addActionButton(section, "Apply tighter defaults") {
            miniPlayerToggleManager.setMiniPlayerStyle(MiniPlayerToggleManager.STYLE_COMPACT)
            persistAppearance(
                AppearancePreferences().copy(
                    buttonSizeScale = 0.88f,
                    miniPlayerHeightDp = 60,
                    miniPlayerCompactMode = true,
                    cardCornerRadiusDp = 18
                )
            )
            Toast.makeText(requireContext(), "Compact defaults applied.", Toast.LENGTH_SHORT).show()
        }

        addActionButton(section, "Reset appearance", outlined = true) {
            miniPlayerToggleManager.setMiniPlayerStyle(MiniPlayerToggleManager.STYLE_REVAMPED)
            persistAppearance(AppearancePreferences())
            Toast.makeText(requireContext(), "Appearance reset to a stable default.", Toast.LENGTH_SHORT).show()
        }
    }

    private fun persistAppearance(updatedPrefs: AppearancePreferences) {
        currentPrefs = updatedPrefs
        currentPrefs.saveToPrefs(requireContext())
        ThemeManager.broadcastChange(requireContext(), false)
        refreshSummary()
    }

    private fun refreshSummary() {
        val miniPlayerStyle = miniPlayerToggleManager.getAvailableStyles()
            .firstOrNull { it.first == miniPlayerToggleManager.getMiniPlayerStyle() }
            ?.second
            ?: "Deck"

        setupSummaryView.text = buildString {
            append("Now Playing: ${currentPrefs.nowPlayingLayoutTheme.displayName}")
            append(" • Mini Player: $miniPlayerStyle")
            append(" • Art ${if (currentPrefs.miniPlayerShowArt) "On" else "Off"}")
            append(" • Artist ${if (currentPrefs.miniPlayerShowArtist) "On" else "Off"}")
        }

        densitySummaryView.text = buildString {
            append("Controls ${(currentPrefs.buttonSizeScale * 100).roundToInt()}%")
            append(" • Text ${(currentPrefs.fontScale * 100).roundToInt()}%")
            append(" • Mini Player ${currentPrefs.miniPlayerHeightDp}dp")
            append(" • Corners ${currentPrefs.cardCornerRadiusDp}dp")
        }
    }
}
