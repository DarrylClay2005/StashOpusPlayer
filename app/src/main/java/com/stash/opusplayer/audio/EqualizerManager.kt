package com.stash.opusplayer.audio

import android.content.Context
import android.content.SharedPreferences
import android.media.audiofx.Equalizer
import android.media.audiofx.BassBoost
import android.media.audiofx.Virtualizer
import android.media.audiofx.PresetReverb
import android.media.audiofx.LoudnessEnhancer
import android.media.audiofx.EnvironmentalReverb
import android.os.Bundle
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
    
    private val _currentPreset = MutableStateFlow(EqualizerPreset.NORMAL)
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
        if (setEnabledIfPresent("equalizer", enabled, equalizer?.let { { it.enabled = enabled } })) successfulEffects++
        if (setEnabledIfPresent("bassBoost", enabled, bassBoost?.let { { it.enabled = enabled } })) successfulEffects++
        if (setEnabledIfPresent("virtualizer", enabled, virtualizer?.let { { it.enabled = enabled } })) successfulEffects++
        if (setEnabledIfPresent("presetReverb", enabled, presetReverb?.let { { it.enabled = enabled } })) successfulEffects++
        if (setEnabledIfPresent("loudnessEnhancer", enabled, loudnessEnhancer?.let { { it.enabled = enabled } })) successfulEffects++
        if (setEnabledIfPresent("environmentalReverb", enabled, environmentalReverb?.let { { it.enabled = enabled } })) successfulEffects++
        
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
                    EqualizerPreset.SURROUND_3D -> applySurround3DPreset(eq)
                    EqualizerPreset.CONCERT_HALL -> applyConcertHallPreset(eq)
                    EqualizerPreset.STADIUM -> applyStadiumPreset(eq)
                    EqualizerPreset.ACOUSTIC -> applyAcousticPreset(eq)
                    EqualizerPreset.ELECTRONIC -> applyElectronicPreset(eq)
                    EqualizerPreset.LOUNGE -> applyLoungePreset(eq)
                    EqualizerPreset.SUPER_BASS_BOOST -> applySuperBassBoostPreset(eq)
                    EqualizerPreset.SUPER_REVERB -> applySuperReverbPreset(eq)
                    EqualizerPreset.HIGH_RESOLUTION -> applyHighResolutionPreset(eq)
                    EqualizerPreset.LOFI -> applyLoFiPreset(eq)
                    EqualizerPreset.AUTOTUNE -> applyAutotunePreset(eq)
                    EqualizerPreset.FAN_EFFECT -> applyFanEffectPreset(eq)
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
                if (band !in 0 until eq.numberOfBands.toInt()) {
                    Log.w(TAG, "Ignoring out-of-range band index: $band")
                    return
                }
                val millibels = clampBandLevel(eq, (level * 1000f).toInt())
                eq.setBandLevel(band.toShort(), millibels)

                if (_currentPreset.value != EqualizerPreset.CUSTOM) {
                    _currentPreset.value = EqualizerPreset.CUSTOM
                    prefs.edit().putString(PREF_EQ_PRESET, EqualizerPreset.CUSTOM.name).apply()
                }
                saveCustomBands()
                updateBandLevels()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error setting band level", e)
        }
    }
    
    fun setBassBoost(strength: Int) {
        try {
            val safeStrength = strength.coerceIn(0, 1000)
            bassBoost?.setStrength(safeStrength.toShort())
            _bassBoostLevel.value = safeStrength
            prefs.edit().putInt(PREF_BASS_BOOST, safeStrength).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Error setting bass boost", e)
        }
    }
    
    fun setVirtualizer(strength: Int) {
        try {
            val safeStrength = strength.coerceIn(0, 1000)
            virtualizer?.setStrength(safeStrength.toShort())
            _virtualizerLevel.value = safeStrength
            prefs.edit().putInt(PREF_VIRTUALIZER, safeStrength).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Error setting virtualizer", e)
        }
    }
    
    fun setReverbPreset(preset: Int) {
        try {
            presetReverb?.preset = preset.toShort()
            _reverbPreset.value = preset
            prefs.edit().putInt(PREF_REVERB, preset).apply()
        } catch (e: Exception) {
            Log.e(TAG, "Error setting reverb preset", e)
        }
    }
    
    fun setLoudnessGain(gain: Int) {
        try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.KITKAT) {
                loudnessEnhancer?.setTargetGain(gain)
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
            equalizer?.getCenterFreq(band.toShort())?.div(1000) ?: defaultBandFrequency(band)
        } catch (e: Exception) {
            defaultBandFrequency(band)
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

    fun getPreviewBandLevels(preset: EqualizerPreset = _currentPreset.value): List<Float> {
        val bandCount = getNumberOfBands().coerceAtLeast(1)
        if (preset == EqualizerPreset.CUSTOM) {
            val customBands = prefs.getString(PREF_CUSTOM_BANDS, null)
                ?.split(",")
                ?.mapNotNull { it.toIntOrNull() }
                .orEmpty()
            return List(bandCount) { index ->
                customBands.getOrNull(index)?.div(1000f) ?: 0f
            }
        }

        val rawLevels = presetLevels(preset)
        return List(bandCount) { index ->
            rawLevels.getOrNull(index)?.div(1000f) ?: 0f
        }
    }

    fun createStateBundle(): Bundle {
        val range = getBandRange()
        val frequencies = IntArray(getNumberOfBands()) { index -> getBandFrequency(index) }
        val levels = if (_bandLevels.value.isNotEmpty()) {
            _bandLevels.value.toFloatArray()
        } else {
            getPreviewBandLevels().toFloatArray()
        }
        return Bundle().apply {
            putBoolean("enabled", _isEnabled.value)
            putString("preset", _currentPreset.value.name)
            putInt("band_range_min", range.first)
            putInt("band_range_max", range.second)
            putIntArray("band_frequencies", frequencies)
            putFloatArray("band_levels", levels)
            putInt("bass_boost", _bassBoostLevel.value)
            putInt("virtualizer", _virtualizerLevel.value)
            putInt("reverb_preset", _reverbPreset.value)
            putInt("loudness_gain", _loudnessGain.value)
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
    
    // Enhanced preset implementations with more sophisticated curves
    private fun applyRockPreset(eq: Equalizer) {
        val levels = intArrayOf(800, 600, 300, -200, -400, -200, 400, 700, 1000, 1200, 1300, 1200)
        applyLevels(eq, levels)
        setBassBoost(600)  // Enhanced bass for rock
        setVirtualizer(400)  // Moderate spatial enhancement
    }
    
    private fun applyPopPreset(eq: Equalizer) {
        val levels = intArrayOf(-100, 300, 600, 800, 700, 500, 200, -100, -200, -300, -200, -100)
        applyLevels(eq, levels)
        setBassBoost(400)  // Controlled bass
        setVirtualizer(600)  // Enhanced stereo imaging for pop
        setLoudnessGain(300)  // Slight loudness enhancement
    }
    
    private fun applyJazzPreset(eq: Equalizer) {
        val levels = intArrayOf(300, 200, 100, 300, 400, 300, 200, 300, 400, 500, 400, 300)
        applyLevels(eq, levels)
        setBassBoost(200)  // Subtle bass enhancement
        setVirtualizer(700)  // Enhanced spatial for jazz instruments
        setEnvironmentalReverb(400, 2000)  // Jazz club ambiance
    }
    
    private fun applyClassicalPreset(eq: Equalizer) {
        val levels = intArrayOf(400, 300, 100, -100, -200, -100, 200, 400, 600, 700, 800, 600)
        applyLevels(eq, levels)
        setBassBoost(100)  // Natural bass response
        setVirtualizer(800)  // Wide soundstage for orchestral music
        setEnvironmentalReverb(600, 3500)  // Concert hall acoustics
        setLoudnessGain(200)  // Maintain dynamic range
    }
    
    private fun applyDancePreset(eq: Equalizer) {
        val levels = intArrayOf(1200, 1000, 600, 200, 100, -200, -400, -300, 200, 400, 600, 500)
        applyLevels(eq, levels)
        setBassBoost(800)  // Strong bass for dance music
        setVirtualizer(700)  // Enhanced spatial imaging
        setLoudnessGain(500)  // Increased perceived loudness
    }
    
    private fun applyMetalPreset(eq: Equalizer) {
        val levels = intArrayOf(1000, 800, 600, 1000, 1200, 800, 600, 1000, 1100, 1300, 1400, 1300)
        applyLevels(eq, levels)
        setBassBoost(700)  // Powerful bass for metal
        setVirtualizer(500)  // Controlled spatial enhancement
        setLoudnessGain(400)  // Enhanced punch and presence
    }
    
    private fun applyBassBoostPreset(eq: Equalizer) {
        val levels = intArrayOf(1200, 800, 400, 0, 0, 0, 0, 0, 0, 0)
        applyLevels(eq, levels)
    }
    
    private fun applyVocalPreset(eq: Equalizer) {
        val levels = intArrayOf(-200, -300, -300, 200, 400, 400, 300, 200, 0, -200)
        applyLevels(eq, levels)
    }
    
    private fun applySurround3DPreset(eq: Equalizer) {
        // Enhance spatial frequencies and add depth
        val levels = intArrayOf(300, 200, 100, 300, 500, 600, 700, 800, 600, 400)
        applyLevels(eq, levels)
        // Enable virtualizer for 3D effect
        setVirtualizer(800)
    }
    
    private fun applyConcertHallPreset(eq: Equalizer) {
        // Simulate concert hall acoustics with enhanced reverb
        val levels = intArrayOf(200, 300, 100, 200, 300, 400, 500, 400, 300, 200)
        applyLevels(eq, levels)
        setVirtualizer(600)
    }
    
    private fun applyStadiumPreset(eq: Equalizer) {
        // Large venue sound with powerful bass and clear highs
        val levels = intArrayOf(800, 600, 400, 200, 100, 200, 400, 600, 800, 900)
        applyLevels(eq, levels)
        setBassBoost(700)
        setVirtualizer(500)
    }
    
    private fun applyAcousticPreset(eq: Equalizer) {
        // Natural acoustic sound with warm mids
        val levels = intArrayOf(300, 400, 300, 400, 500, 400, 300, 200, 100, 100)
        applyLevels(eq, levels)
        setVirtualizer(300)
    }
    
    private fun applyElectronicPreset(eq: Equalizer) {
        // Electronic music with enhanced bass and treble
        val levels = intArrayOf(1000, 800, 600, 200, 100, 200, 600, 800, 1000, 1100)
        applyLevels(eq, levels)
        setBassBoost(800)
        setVirtualizer(700)
    }
    
    private fun applyLoungePreset(eq: Equalizer) {
        // Smooth, relaxed sound for ambient music
        val levels = intArrayOf(200, 300, 400, 500, 400, 300, 200, 100, 0, -100)
        applyLevels(eq, levels)
        setVirtualizer(400)
    }
    
    private fun applySuperBassBoostPreset(eq: Equalizer) {
        // Extreme bass enhancement with sub-bass focus
        val levels = intArrayOf(1500, 1200, 800, 400, 200, 100, 0, 0, 200, 400)
        applyLevels(eq, levels)
        setBassBoost(1000) // Maximum bass boost
        setLoudnessGain(800) // Enhanced loudness for impact
        setVirtualizer(600)
    }
    
    private fun applySuperReverbPreset(eq: Equalizer) {
        // Cathedral-like reverb with spatial enhancement
        val levels = intArrayOf(400, 300, 200, 400, 600, 700, 600, 500, 400, 300)
        applyLevels(eq, levels)
        setReverbPreset(PresetReverb.PRESET_LARGEHALL.toInt())
        setEnvironmentalReverb(800, 5000) // Large room, long decay
        setVirtualizer(900)
    }
    
    private fun applyHighResolutionPreset(eq: Equalizer) {
        // Audiophile-grade clarity and detail enhancement
        val levels = intArrayOf(100, 200, 300, 400, 500, 600, 700, 800, 900, 1000)
        applyLevels(eq, levels)
        setLoudnessGain(600) // Enhance dynamic range
        setVirtualizer(700) // Spatial clarity
        setBassBoost(300) // Controlled bass
    }
    
    private fun applyLoFiPreset(eq: Equalizer) {
        // Vintage lo-fi sound with warm, compressed characteristics
        val levels = intArrayOf(600, 400, 200, 300, 400, 200, -200, -400, -600, -800)
        applyLevels(eq, levels)
        setBassBoost(600) // Warm bass
        setVirtualizer(200) // Reduced spatial to simulate analog
        setReverbPreset(PresetReverb.PRESET_SMALLROOM.toInt()) // Intimate space
    }
    
    private fun applyAutotunePreset(eq: Equalizer) {
        // Vocal enhancement with harmonic emphasis
        val levels = intArrayOf(-200, -100, 200, 600, 800, 700, 500, 300, 100, -100)
        applyLevels(eq, levels)
        setVirtualizer(800) // Spatial vocal enhancement
        setEnvironmentalReverb(300, 1500) // Studio-like reverb
        setLoudnessGain(400) // Vocal presence
    }
    
    private fun applyFanEffectPreset(eq: Equalizer) {
        // Simulates the whooshing effect of a fan with modulated frequencies
        val levels = intArrayOf(800, 600, 400, 600, 800, 600, 400, 200, 400, 600)
        applyLevels(eq, levels)
        setVirtualizer(900) // Maximum spatial effect
        setEnvironmentalReverb(600, 2000) // Medium room with moderate decay
        setBassBoost(400) // Low-frequency emphasis for whoosh effect
    }
    
    private fun applyLevels(eq: Equalizer, levels: IntArray) {
        val totalBands = eq.numberOfBands.toInt()
        val numBands = minOf(totalBands, levels.size)
        for (i in 0 until numBands) {
            eq.setBandLevel(i.toShort(), clampBandLevel(eq, levels[i]))
        }
        for (i in numBands until totalBands) {
            eq.setBandLevel(i.toShort(), 0)
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

    private fun setEnabledIfPresent(effectName: String, enabled: Boolean, setter: (() -> Unit)?): Boolean {
        if (setter == null) {
            return false
        }
        return try {
            setter()
            true
        } catch (e: Exception) {
            Log.w(TAG, "Failed to set $effectName enabled=$enabled", e)
            false
        }
    }

    private fun clampBandLevel(eq: Equalizer, millibels: Int): Short {
        val range = eq.bandLevelRange
        return millibels.coerceIn(range[0].toInt(), range[1].toInt()).toShort()
    }

    private fun defaultBandFrequency(band: Int): Int {
        val fallbackBands = intArrayOf(60, 230, 910, 3600, 14000)
        return fallbackBands.getOrElse(band) { fallbackBands.last() }
    }

    private fun presetLevels(preset: EqualizerPreset): IntArray = when (preset) {
        EqualizerPreset.NORMAL -> intArrayOf(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        EqualizerPreset.ROCK -> intArrayOf(800, 600, 300, -200, -400, -200, 400, 700, 1000, 1200, 1300, 1200)
        EqualizerPreset.POP -> intArrayOf(-100, 300, 600, 800, 700, 500, 200, -100, -200, -300, -200, -100)
        EqualizerPreset.JAZZ -> intArrayOf(300, 200, 100, 300, 400, 300, 200, 300, 400, 500, 400, 300)
        EqualizerPreset.CLASSICAL -> intArrayOf(400, 300, 100, -100, -200, -100, 200, 400, 600, 700, 800, 600)
        EqualizerPreset.DANCE -> intArrayOf(1200, 1000, 600, 200, 100, -200, -400, -300, 200, 400, 600, 500)
        EqualizerPreset.METAL -> intArrayOf(1000, 800, 600, 1000, 1200, 800, 600, 1000, 1100, 1300, 1400, 1300)
        EqualizerPreset.BASS_BOOST -> intArrayOf(1200, 800, 400, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        EqualizerPreset.VOCAL -> intArrayOf(-200, -300, -300, 200, 400, 400, 300, 200, 0, -200, 0, 0)
        EqualizerPreset.SURROUND_3D -> intArrayOf(300, 200, 100, 300, 500, 600, 700, 800, 600, 400, 0, 0)
        EqualizerPreset.CONCERT_HALL -> intArrayOf(200, 300, 100, 200, 300, 400, 500, 400, 300, 200, 0, 0)
        EqualizerPreset.STADIUM -> intArrayOf(800, 600, 400, 200, 100, 200, 400, 600, 800, 900, 0, 0)
        EqualizerPreset.ACOUSTIC -> intArrayOf(300, 400, 300, 400, 500, 400, 300, 200, 100, 100, 0, 0)
        EqualizerPreset.ELECTRONIC -> intArrayOf(1000, 800, 600, 200, 100, 200, 600, 800, 1000, 1100, 0, 0)
        EqualizerPreset.LOUNGE -> intArrayOf(200, 300, 400, 500, 400, 300, 200, 100, 0, -100, 0, 0)
        EqualizerPreset.SUPER_BASS_BOOST -> intArrayOf(1500, 1200, 800, 400, 200, 100, 0, 0, 200, 400, 0, 0)
        EqualizerPreset.SUPER_REVERB -> intArrayOf(400, 300, 200, 400, 600, 700, 600, 500, 400, 300, 0, 0)
        EqualizerPreset.HIGH_RESOLUTION -> intArrayOf(100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 0, 0)
        EqualizerPreset.LOFI -> intArrayOf(600, 400, 200, 300, 400, 200, -200, -400, -600, -800, 0, 0)
        EqualizerPreset.AUTOTUNE -> intArrayOf(-200, -100, 200, 600, 800, 700, 500, 300, 100, -100, 0, 0)
        EqualizerPreset.FAN_EFFECT -> intArrayOf(800, 600, 400, 600, 800, 600, 400, 200, 400, 600, 0, 0)
        EqualizerPreset.CUSTOM -> prefs.getString(PREF_CUSTOM_BANDS, null)
            ?.split(",")
            ?.mapNotNull { it.toIntOrNull() }
            ?.toIntArray()
            ?: intArrayOf()
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
    SURROUND_3D,
    CONCERT_HALL,
    STADIUM,
    ACOUSTIC,
    ELECTRONIC,
    LOUNGE,
    SUPER_BASS_BOOST,
    SUPER_REVERB,
    HIGH_RESOLUTION,
    LOFI,
    AUTOTUNE,
    FAN_EFFECT,
    CUSTOM
}
