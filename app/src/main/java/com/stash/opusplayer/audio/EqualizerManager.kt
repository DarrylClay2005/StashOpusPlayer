package com.stash.opusplayer.audio

import android.content.Context
import android.content.SharedPreferences
import android.media.audiofx.Equalizer
import android.media.audiofx.BassBoost
import android.media.audiofx.Virtualizer
import android.media.audiofx.PresetReverb
import android.media.audiofx.LoudnessEnhancer
import android.media.audiofx.EnvironmentalReverb
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
        private const val PREF_REVERB = "reverb_preset"
        private const val PREF_LOUDNESS_ENHANCER = "loudness_enhancer_gain"
        private const val PREF_ENV_REVERB_ROOM_SIZE = "env_reverb_room_size"
        private const val PREF_ENV_REVERB_DECAY_TIME = "env_reverb_decay_time"
        private const val PREF_CUSTOM_BANDS = "custom_eq_bands"
    }
    
    private val prefs: SharedPreferences = PreferenceManager.getDefaultSharedPreferences(context)
    
    private var equalizer: Equalizer? = null
    private var bassBoost: BassBoost? = null
    private var virtualizer: Virtualizer? = null
    private var presetReverb: PresetReverb? = null
    private var loudnessEnhancer: LoudnessEnhancer? = null
    private var environmentalReverb: EnvironmentalReverb? = null
    
    private val _isEnabled = MutableStateFlow(false)
    val isEnabled: StateFlow<Boolean> = _isEnabled.asStateFlow()
    
    private val _currentPreset = MutableStateFlow(EqualizerPreset.FLAT)
    val currentPreset: StateFlow<EqualizerPreset> = _currentPreset.asStateFlow()
    
    private val _bandLevels = MutableStateFlow<List<Float>>(emptyList())
    val bandLevels: StateFlow<List<Float>> = _bandLevels.asStateFlow()
    
    private val _bassBoostLevel = MutableStateFlow(0)
    val bassBoostLevel: StateFlow<Int> = _bassBoostLevel.asStateFlow()
    
    private val _virtualizerLevel = MutableStateFlow(0)
    val virtualizerLevel: StateFlow<Int> = _virtualizerLevel.asStateFlow()
    
    private val _reverbPreset = MutableStateFlow(0)
    val reverbPreset: StateFlow<Int> = _reverbPreset.asStateFlow()
    
    private val _loudnessGain = MutableStateFlow(0)
    val loudnessGain: StateFlow<Int> = _loudnessGain.asStateFlow()
    
    private val _envReverbRoomSize = MutableStateFlow(0)
    val envReverbRoomSize: StateFlow<Int> = _envReverbRoomSize.asStateFlow()
    
    private val _envReverbDecayTime = MutableStateFlow(0)
    val envReverbDecayTime: StateFlow<Int> = _envReverbDecayTime.asStateFlow()
    
    fun initialize(audioSessionId: Int) {
        try {
            // Release existing instances
            release()
            
            Log.d(TAG, "Initializing equalizer with audio session: $audioSessionId")
            
            // Create new audio effects with better error handling
            try {
                equalizer = Equalizer(0, audioSessionId).apply {
                    enabled = false // Start disabled, enable after full setup
                }
                Log.d(TAG, "Equalizer created successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to create Equalizer", e)
                // Continue with other effects even if equalizer fails
            }
            
            // Initialize BassBoost with error handling
            try {
                bassBoost = BassBoost(0, audioSessionId).apply {
                    enabled = false
                    setStrength(prefs.getInt(PREF_BASS_BOOST, 0).toShort())
                }
                Log.d(TAG, "BassBoost created successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to create BassBoost", e)
            }
            
            // Initialize Virtualizer with error handling
            try {
                virtualizer = Virtualizer(0, audioSessionId).apply {
                    enabled = false
                    setStrength(prefs.getInt(PREF_VIRTUALIZER, 0).toShort())
                }
                Log.d(TAG, "Virtualizer created successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to create Virtualizer", e)
            }
            
            // Initialize PresetReverb with error handling
            try {
                presetReverb = PresetReverb(0, audioSessionId).apply {
                    enabled = false
                    preset = prefs.getInt(PREF_REVERB, PresetReverb.PRESET_NONE.toInt()).toShort()
                }
                Log.d(TAG, "PresetReverb created successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to create PresetReverb", e)
            }
            
            // Initialize LoudnessEnhancer for high-resolution and super bass effects
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.KITKAT) {
                try {
                    loudnessEnhancer = LoudnessEnhancer(audioSessionId).apply {
                        enabled = prefs.getBoolean(PREF_EQ_ENABLED, false)
                        setTargetGain(prefs.getInt(PREF_LOUDNESS_ENHANCER, 0))
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "LoudnessEnhancer not supported on this device", e)
                }
            }
            
            // Initialize EnvironmentalReverb for advanced reverb effects
            try {
                environmentalReverb = EnvironmentalReverb(0, audioSessionId).apply {
                    enabled = prefs.getBoolean(PREF_EQ_ENABLED, false)
                    setRoomLevel(prefs.getInt(PREF_ENV_REVERB_ROOM_SIZE, 0).toShort())
                    decayTime = prefs.getInt(PREF_ENV_REVERB_DECAY_TIME, 1000)
                }
            } catch (e: Exception) {
                Log.w(TAG, "EnvironmentalReverb not supported on this device", e)
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
            presetReverb?.release()
            loudnessEnhancer?.release()
            environmentalReverb?.release()
            
            equalizer = null
            bassBoost = null
            virtualizer = null
            presetReverb = null
            loudnessEnhancer = null
            environmentalReverb = null
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing equalizer", e)
        }
    }
    
    fun setEnabled(enabled: Boolean) {
        var successfulEffects = 0
        val totalEffects = 6
        
        // Enable/disable each effect independently with isolated error handling
        // For auxiliary effects, only enable if they have non-zero values
        try {
            equalizer?.enabled = enabled
            successfulEffects++
        } catch (e: Exception) {
            Log.w(TAG, "Failed to set equalizer enabled state", e)
        }
        
        try {
            bassBoost?.let { bb ->
                // Only enable if the effect has a non-zero strength
                bb.enabled = enabled && (bb.roundedStrength > 0)
                successfulEffects++
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to set bassBoost enabled state", e)
        }
        
        try {
            virtualizer?.let { v ->
                // Only enable if the effect has a non-zero strength
                v.enabled = enabled && (v.roundedStrength > 0)
                successfulEffects++
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to set virtualizer enabled state", e)
        }
        
        try {
            presetReverb?.let { r ->
                // Only enable if preset is not NONE
                r.enabled = enabled && (r.preset != PresetReverb.PRESET_NONE)
                successfulEffects++
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to set presetReverb enabled state", e)
        }
        
        try {
            loudnessEnhancer?.let { le ->
                // Only enable if gain is non-zero
                val currentGain = prefs.getInt(PREF_LOUDNESS_ENHANCER, 0)
                le.enabled = enabled && (currentGain > 0)
                successfulEffects++
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to set loudnessEnhancer enabled state", e)
        }
        
        try {
            environmentalReverb?.let { er ->
                // Only enable if room size or decay time is significant
                val roomSize = prefs.getInt(PREF_ENV_REVERB_ROOM_SIZE, 0)
                val decayTime = prefs.getInt(PREF_ENV_REVERB_DECAY_TIME, 1000)
                er.enabled = enabled && (roomSize > 0 || decayTime > 1000)
                successfulEffects++
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to set environmentalReverb enabled state", e)
        }
        
        // Update state if at least some effects were successful
        val effectivelyEnabled = enabled && (successfulEffects > 0)
        _isEnabled.value = effectivelyEnabled
        
        try {
            prefs.edit().putBoolean(PREF_EQ_ENABLED, effectivelyEnabled).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save equalizer enabled state", e)
        }
        
        Log.d(TAG, "Equalizer effects enabled: $effectivelyEnabled ($successfulEffects/$totalEffects effects working)")
    }
    
    fun setPreset(preset: EqualizerPreset) {
        try {
            equalizer?.let { eq ->
                // Reset all auxiliary effects to sane defaults before applying the preset
                resetEffectsToDefaults()
                when (preset) {
                    EqualizerPreset.FLAT -> {
                        // Reset all bands to 0
                        for (i in 0 until eq.numberOfBands) {
                            eq.setBandLevel(i.toShort(), 0)
                        }
                    }
                    EqualizerPreset.BASS_BOOST -> applyBassBoostPreset(eq)
                    EqualizerPreset.VOCAL_CLARITY -> applyVocalClarityPreset(eq)
                    EqualizerPreset.CLASSICAL -> applyClassicalPreset(eq)
                    EqualizerPreset.ROCK -> applyRockPreset(eq)
                    EqualizerPreset.JAZZ -> applyJazzPreset(eq)
                    EqualizerPreset.ELECTRONIC -> applyElectronicPreset(eq)
                    EqualizerPreset.HIP_HOP -> applyHipHopPreset(eq)
                    EqualizerPreset.ACOUSTIC -> applyAcousticPreset(eq)
                    EqualizerPreset.TREBLE_BOOST -> applyTrebleBoostPreset(eq)
                    EqualizerPreset.CUSTOM -> loadCustomBands(eq)
                }
                
                _currentPreset.value = preset
                prefs.edit().putString(PREF_EQ_PRESET, preset.name).apply()
                updateBandLevels()
                
                // Always enable the equalizer when a preset is applied (except FLAT)
                if (preset != EqualizerPreset.FLAT) {
                    // Enable the equalizer effect itself first
                    try {
                        eq.enabled = true
                        _isEnabled.value = true
                        prefs.edit().putBoolean(PREF_EQ_ENABLED, true).apply()
                        Log.d(TAG, "Enabled equalizer for preset: $preset")
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to enable equalizer for preset", e)
                    }
                    
                    // Then re-enable all effects with new values
                    setEnabled(true)
                    Log.d(TAG, "Applied and enabled preset: $preset")
                }
                if (_isEnabled.value && preset == EqualizerPreset.FLAT) {
                    // For FLAT preset, just re-evaluate if already enabled
                    setEnabled(true)
                }
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
            bassBoost?.let { bb ->
                bb.setStrength(strength.toShort())
                // Enable the effect if strength > 0 and equalizer is enabled
                if (_isEnabled.value) {
                    bb.enabled = (strength > 0)
                }
            }
            _bassBoostLevel.value = strength
            prefs.edit().putInt(PREF_BASS_BOOST, strength).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Error setting bass boost", e)
        }
    }
    
    fun setVirtualizer(strength: Int) {
        try {
            virtualizer?.let { v ->
                v.setStrength(strength.toShort())
                // Enable the effect if strength > 0 and equalizer is enabled
                if (_isEnabled.value) {
                    v.enabled = (strength > 0)
                }
            }
            _virtualizerLevel.value = strength
            prefs.edit().putInt(PREF_VIRTUALIZER, strength).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Error setting virtualizer", e)
        }
    }
    
    fun setReverbPreset(preset: Int) {
        try {
            presetReverb?.let { r ->
                r.preset = preset.toShort()
                // Enable the effect if preset is not NONE and equalizer is enabled
                if (_isEnabled.value) {
                    r.enabled = (preset != PresetReverb.PRESET_NONE.toInt())
                }
            }
            _reverbPreset.value = preset
            prefs.edit().putInt(PREF_REVERB, preset).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Error setting reverb preset", e)
        }
    }
    
    fun setLoudnessGain(gain: Int) {
        try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.KITKAT) {
                loudnessEnhancer?.let { le ->
                    le.setTargetGain(gain)
                    // Enable the effect if gain > 0 and equalizer is enabled
                    if (_isEnabled.value) {
                        le.enabled = (gain > 0)
                    }
                }
                _loudnessGain.value = gain
                prefs.edit().putInt(PREF_LOUDNESS_ENHANCER, gain).apply()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error setting loudness gain", e)
        }
    }
    
    fun setEnvironmentalReverb(roomSize: Int, decayTime: Int) {
        try {
            environmentalReverb?.let { reverb ->
                reverb.setRoomLevel(roomSize.toShort())
                reverb.decayTime = decayTime
                // Enable the effect if roomSize > 0 and equalizer is enabled
                if (_isEnabled.value) {
                    reverb.enabled = (roomSize > 0 || decayTime > 1000)
                }
                _envReverbRoomSize.value = roomSize
                _envReverbDecayTime.value = decayTime
                prefs.edit()
                    .putInt(PREF_ENV_REVERB_ROOM_SIZE, roomSize)
                    .putInt(PREF_ENV_REVERB_DECAY_TIME, decayTime)
                    .apply()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error setting environmental reverb", e)
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
        val presetName = prefs.getString(PREF_EQ_PRESET, EqualizerPreset.FLAT.name)
        val preset = try {
            EqualizerPreset.valueOf(presetName ?: EqualizerPreset.FLAT.name)
        } catch (e: Exception) {
            EqualizerPreset.FLAT
        }
        
        setEnabled(enabled)
        setPreset(preset)
        setBassBoost(prefs.getInt(PREF_BASS_BOOST, 0))
        setVirtualizer(prefs.getInt(PREF_VIRTUALIZER, 0))
        setReverbPreset(prefs.getInt(PREF_REVERB, PresetReverb.PRESET_NONE.toInt()))
        setLoudnessGain(prefs.getInt(PREF_LOUDNESS_ENHANCER, 0))
        setEnvironmentalReverb(
            prefs.getInt(PREF_ENV_REVERB_ROOM_SIZE, 0),
            prefs.getInt(PREF_ENV_REVERB_DECAY_TIME, 1000)
        )
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
        
        presetReverb?.let { r ->
            _reverbPreset.value = r.preset.toInt()
        }
        
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.KITKAT) {
            loudnessEnhancer?.let { _ ->
                _loudnessGain.value = prefs.getInt(PREF_LOUDNESS_ENHANCER, 0)
            }
        }
        
        environmentalReverb?.let { er ->
            _envReverbRoomSize.value = er.getRoomLevel().toInt()
            _envReverbDecayTime.value = er.decayTime
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
    
    private fun resetEffectsToDefaults() {
        try {
            setBassBoost(0)
            setVirtualizer(0)
            setReverbPreset(PresetReverb.PRESET_NONE.toInt())
            setLoudnessGain(0)
            setEnvironmentalReverb(0, 1000)
        } catch (_: Exception) {}
    }
    
    // AI-Powered preset implementations
    private fun applyBassBoostPreset(eq: Equalizer) {
        val levels = intArrayOf(800, 600, 400, 200, 0, -100, -200, -200, -200, -200)
        applyLevels(eq, levels)
        setBassBoost(800)
        setVirtualizer(500)
    }
    
    private fun applyVocalClarityPreset(eq: Equalizer) {
        val levels = intArrayOf(-200, -100, 0, 200, 400, 500, 400, 200, 0, -100)
        applyLevels(eq, levels)
        setBassBoost(0)
        setVirtualizer(300)
    }
    
    private fun applyClassicalPreset(eq: Equalizer) {
        val levels = intArrayOf(0, 0, 0, 0, 0, 0, -200, -200, -300, -400)
        applyLevels(eq, levels)
        setBassBoost(0)
        setVirtualizer(600)
        setReverbPreset(android.media.audiofx.PresetReverb.PRESET_LARGEHALL.toInt())
    }
    
    private fun applyRockPreset(eq: Equalizer) {
        val levels = intArrayOf(500, 400, 300, 200, 0, 200, 400, 500, 500, 500)
        applyLevels(eq, levels)
        setBassBoost(400)
        setVirtualizer(400)
        setReverbPreset(android.media.audiofx.PresetReverb.PRESET_LARGEROOM.toInt())
    }
    
    private fun applyJazzPreset(eq: Equalizer) {
        val levels = intArrayOf(400, 300, 200, 100, 0, 0, 0, 100, 200, 300)
        applyLevels(eq, levels)
        setBassBoost(200)
        setVirtualizer(500)
        setReverbPreset(android.media.audiofx.PresetReverb.PRESET_PLATE.toInt())
    }
    
    private fun applyElectronicPreset(eq: Equalizer) {
        val levels = intArrayOf(600, 500, 400, 0, -100, 0, 300, 500, 600, 700)
        applyLevels(eq, levels)
        setBassBoost(600)
        setVirtualizer(700)
    }
    
    private fun applyHipHopPreset(eq: Equalizer) {
        val levels = intArrayOf(700, 600, 500, 200, 0, 100, 200, 300, 300, 300)
        applyLevels(eq, levels)
        setBassBoost(900)
        setVirtualizer(400)
    }
    
    private fun applyAcousticPreset(eq: Equalizer) {
        val levels = intArrayOf(300, 200, 100, 0, 100, 200, 200, 200, 100, 0)
        applyLevels(eq, levels)
        setBassBoost(100)
        setVirtualizer(300)
        setReverbPreset(android.media.audiofx.PresetReverb.PRESET_SMALLROOM.toInt())
    }
    
    private fun applyTrebleBoostPreset(eq: Equalizer) {
        val levels = intArrayOf(-200, -200, -100, 0, 100, 200, 400, 600, 700, 800)
        applyLevels(eq, levels)
        setBassBoost(0)
        setVirtualizer(400)
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
    
    fun isInitialized(): Boolean {
        return equalizer != null
    }
}

enum class EqualizerPreset {
    FLAT,
    BASS_BOOST,
    VOCAL_CLARITY,
    CLASSICAL,
    ROCK,
    JAZZ,
    ELECTRONIC,
    HIP_HOP,
    ACOUSTIC,
    TREBLE_BOOST,
    CUSTOM
}
