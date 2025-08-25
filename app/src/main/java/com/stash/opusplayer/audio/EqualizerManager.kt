package com.stash.opusplayer.audio

import android.content.Context
import android.content.SharedPreferences
import android.media.audiofx.Equalizer
import android.media.audiofx.BassBoost
import android.media.audiofx.Virtualizer
import android.util.Log
import androidx.preference.PreferenceManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class EqualizerManager(private val context: Context) {
    
    companion object {
        private const val TAG = "EqualizerManager"
        private const val PREF_EQ_ENABLED = "equalizer_enabled"
        private const val PREF_EQ_PRESET = "equalizer_preset"
        private const val PREF_BASS_BOOST = "bass_boost_strength"
        private const val PREF_VIRTUALIZER = "virtualizer_strength"
        private const val PREF_CUSTOM_BANDS = "custom_eq_bands"
    }
    
    private val prefs: SharedPreferences = PreferenceManager.getDefaultSharedPreferences(context)
    
    private var equalizer: Equalizer? = null
    private var bassBoost: BassBoost? = null
    private var virtualizer: Virtualizer? = null
    
    private val _isEnabled = MutableStateFlow(false)
    val isEnabled: StateFlow<Boolean> = _isEnabled.asStateFlow()
    
    private val _currentPreset = MutableStateFlow(EqualizerPreset.NORMAL)
    val currentPreset: StateFlow<EqualizerPreset> = _currentPreset.asStateFlow()
    
    private val _bandLevels = MutableStateFlow<List<Float>>(emptyList())
    val bandLevels: StateFlow<List<Float>> = _bandLevels.asStateFlow()
    
    private val _bassBoostLevel = MutableStateFlow(0)
    val bassBoostLevel: StateFlow<Int> = _bassBoostLevel.asStateFlow()
    
    private val _virtualizerLevel = MutableStateFlow(0)
    val virtualizerLevel: StateFlow<Int> = _virtualizerLevel.asStateFlow()
    
    fun initialize(audioSessionId: Int) {
        try {
            // Release existing instances
            release()
            
            // Create new audio effects
            equalizer = Equalizer(0, audioSessionId).apply {
                enabled = prefs.getBoolean(PREF_EQ_ENABLED, false)
            }
            
            bassBoost = BassBoost(0, audioSessionId).apply {
                enabled = prefs.getBoolean(PREF_EQ_ENABLED, false)
                setStrength(prefs.getInt(PREF_BASS_BOOST, 0).toShort())
            }
            
            virtualizer = Virtualizer(0, audioSessionId).apply {
                enabled = prefs.getBoolean(PREF_EQ_ENABLED, false)
                setStrength(prefs.getInt(PREF_VIRTUALIZER, 0).toShort())
            }
            
            loadSettings()
            updateStateFlows()
            
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing equalizer", e)
        }
    }
    
    fun release() {
        try {
            equalizer?.release()
            bassBoost?.release()
            virtualizer?.release()
            
            equalizer = null
            bassBoost = null
            virtualizer = null
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing equalizer", e)
        }
    }
    
    fun setEnabled(enabled: Boolean) {
        try {
            equalizer?.enabled = enabled
            bassBoost?.enabled = enabled
            virtualizer?.enabled = enabled
            
            _isEnabled.value = enabled
            prefs.edit().putBoolean(PREF_EQ_ENABLED, enabled).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Error setting equalizer enabled state", e)
        }
    }
    
    fun setPreset(preset: EqualizerPreset) {
        try {
            equalizer?.let { eq ->
                when (preset) {
                    EqualizerPreset.NORMAL -> {
                        // Reset all bands to 0
                        for (i in 0 until eq.numberOfBands) {
                            eq.setBandLevel(i.toShort(), 0)
                        }
                    }
                    EqualizerPreset.ROCK -> applyRockPreset(eq)
                    EqualizerPreset.POP -> applyPopPreset(eq)
                    EqualizerPreset.JAZZ -> applyJazzPreset(eq)
                    EqualizerPreset.CLASSICAL -> applyClassicalPreset(eq)
                    EqualizerPreset.DANCE -> applyDancePreset(eq)
                    EqualizerPreset.METAL -> applyMetalPreset(eq)
                    EqualizerPreset.BASS_BOOST -> applyBassBoostPreset(eq)
                    EqualizerPreset.VOCAL -> applyVocalPreset(eq)
                    EqualizerPreset.CUSTOM -> loadCustomBands(eq)
                }
                
                _currentPreset.value = preset
                prefs.edit().putString(PREF_EQ_PRESET, preset.name).apply()
                updateBandLevels()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error setting equalizer preset", e)
        }
    }
    
    fun setBandLevel(band: Int, level: Float) {
        try {
            equalizer?.let { eq ->
                val millibels = (level * 1000).toInt().toShort()
                eq.setBandLevel(band.toShort(), millibels)
                
                // If we're in custom mode, save the custom settings
                if (_currentPreset.value == EqualizerPreset.CUSTOM) {
                    saveCustomBands()
                }
                
                updateBandLevels()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error setting band level", e)
        }
    }
    
    fun setBassBoost(strength: Int) {
        try {
            bassBoost?.setStrength(strength.toShort())
            _bassBoostLevel.value = strength
            prefs.edit().putInt(PREF_BASS_BOOST, strength).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Error setting bass boost", e)
        }
    }
    
    fun setVirtualizer(strength: Int) {
        try {
            virtualizer?.setStrength(strength.toShort())
            _virtualizerLevel.value = strength
            prefs.edit().putInt(PREF_VIRTUALIZER, strength).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Error setting virtualizer", e)
        }
    }
    
    fun getBandFrequency(band: Int): Int {
        return try {
            equalizer?.getCenterFreq(band.toShort())?.div(1000) ?: 0
        } catch (e: Exception) {
            0
        }
    }
    
    fun getBandRange(): Pair<Int, Int> {
        return try {
            equalizer?.let { eq ->
                val range = eq.bandLevelRange
                Pair(range[0].toInt(), range[1].toInt())
            } ?: Pair(-1500, 1500)
        } catch (e: Exception) {
            Pair(-1500, 1500)
        }
    }
    
    fun getNumberOfBands(): Int {
        return try {
            equalizer?.numberOfBands?.toInt() ?: 5
        } catch (e: Exception) {
            5
        }
    }
    
    private fun loadSettings() {
        val enabled = prefs.getBoolean(PREF_EQ_ENABLED, false)
        val presetName = prefs.getString(PREF_EQ_PRESET, EqualizerPreset.NORMAL.name)
        val preset = try {
            EqualizerPreset.valueOf(presetName ?: EqualizerPreset.NORMAL.name)
        } catch (e: Exception) {
            EqualizerPreset.NORMAL
        }
        
        setEnabled(enabled)
        setPreset(preset)
        setBassBoost(prefs.getInt(PREF_BASS_BOOST, 0))
        setVirtualizer(prefs.getInt(PREF_VIRTUALIZER, 0))
    }
    
    private fun updateStateFlows() {
        equalizer?.let { eq ->
            _isEnabled.value = eq.enabled
            updateBandLevels()
        }
        
        bassBoost?.let { bb ->
            _bassBoostLevel.value = bb.roundedStrength.toInt()
        }
        
        virtualizer?.let { v ->
            _virtualizerLevel.value = v.roundedStrength.toInt()
        }
    }
    
    private fun updateBandLevels() {
        equalizer?.let { eq ->
            val bands = mutableListOf<Float>()
            for (i in 0 until eq.numberOfBands) {
                bands.add(eq.getBandLevel(i.toShort()).toFloat() / 1000f)
            }
            _bandLevels.value = bands
        }
    }
    
    // Preset implementations
    private fun applyRockPreset(eq: Equalizer) {
        val levels = intArrayOf(800, 400, -200, -400, -200, 400, 800, 1100, 1200, 1200)
        applyLevels(eq, levels)
    }
    
    private fun applyPopPreset(eq: Equalizer) {
        val levels = intArrayOf(-200, 400, 700, 800, 500, 0, -200, -200, -200, -200)
        applyLevels(eq, levels)
    }
    
    private fun applyJazzPreset(eq: Equalizer) {
        val levels = intArrayOf(400, 200, 0, 200, -200, -200, 0, 200, 400, 500)
        applyLevels(eq, levels)
    }
    
    private fun applyClassicalPreset(eq: Equalizer) {
        val levels = intArrayOf(500, 300, -200, -200, -200, 0, 200, 300, 400, 500)
        applyLevels(eq, levels)
    }
    
    private fun applyDancePreset(eq: Equalizer) {
        val levels = intArrayOf(1000, 700, 200, 0, 0, -500, -700, -700, 0, 0)
        applyLevels(eq, levels)
    }
    
    private fun applyMetalPreset(eq: Equalizer) {
        val levels = intArrayOf(1000, 500, 1000, 1300, 500, 400, 1000, 1100, 1200, 1300)
        applyLevels(eq, levels)
    }
    
    private fun applyBassBoostPreset(eq: Equalizer) {
        val levels = intArrayOf(1200, 800, 400, 0, 0, 0, 0, 0, 0, 0)
        applyLevels(eq, levels)
    }
    
    private fun applyVocalPreset(eq: Equalizer) {
        val levels = intArrayOf(-200, -300, -300, 200, 400, 400, 300, 200, 0, -200)
        applyLevels(eq, levels)
    }
    
    private fun applyLevels(eq: Equalizer, levels: IntArray) {
        val numBands = minOf(eq.numberOfBands.toInt(), levels.size)
        for (i in 0 until numBands) {
            eq.setBandLevel(i.toShort(), levels[i].toShort())
        }
    }
    
    private fun loadCustomBands(eq: Equalizer) {
        val customBands = prefs.getString(PREF_CUSTOM_BANDS, null)
        if (customBands != null) {
            try {
                val levels = customBands.split(",").map { it.toInt() }
                applyLevels(eq, levels.toIntArray())
            } catch (e: Exception) {
                Log.e(TAG, "Error loading custom bands", e)
            }
        }
    }
    
    private fun saveCustomBands() {
        equalizer?.let { eq ->
            val levels = mutableListOf<String>()
            for (i in 0 until eq.numberOfBands) {
                levels.add(eq.getBandLevel(i.toShort()).toString())
            }
            prefs.edit().putString(PREF_CUSTOM_BANDS, levels.joinToString(",")).apply()
        }
    }
}

enum class EqualizerPreset {
    NORMAL,
    ROCK,
    POP,
    JAZZ,
    CLASSICAL,
    DANCE,
    METAL,
    BASS_BOOST,
    VOCAL,
    CUSTOM
}
