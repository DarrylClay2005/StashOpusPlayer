package com.stash.opusplayer.audio

import android.content.Context
import android.media.MediaMetadataRetriever
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.abs

/**
 * AI-powered audio preset manager that analyzes audio characteristics
 * and automatically suggests optimal EQ and processing settings
 */
class AIAudioPresetManager(private val context: Context) {
    
    companion object {
        private const val TAG = "AIAudioPresetManager"
        
        // Preset definitions based on audio characteristics
        val PRESETS = mapOf(
            "Bass Boost" to AudioPreset(
                name = "Bass Boost",
                description = "Enhanced low frequencies for bass-heavy music",
                eqBands = floatArrayOf(8f, 6f, 4f, 2f, 0f, -1f, -2f, -2f, -2f, -2f),
                reverbPreset = 0,
                bassBoost = 800,
                virtualizer = 500
            ),
            "Vocal Clarity" to AudioPreset(
                name = "Vocal Clarity",
                description = "Optimized for vocal-focused music and podcasts",
                eqBands = floatArrayOf(-2f, -1f, 0f, 2f, 4f, 5f, 4f, 2f, 0f, -1f),
                reverbPreset = 0,
                bassBoost = 0,
                virtualizer = 300
            ),
            "Classical" to AudioPreset(
                name = "Classical",
                description = "Balanced for orchestral and classical music",
                eqBands = floatArrayOf(0f, 0f, 0f, 0f, 0f, 0f, -2f, -2f, -3f, -4f),
                reverbPreset = 4, // Concert hall
                bassBoost = 0,
                virtualizer = 600
            ),
            "Rock" to AudioPreset(
                name = "Rock",
                description = "Punchy mids and treble for rock music",
                eqBands = floatArrayOf(5f, 4f, 3f, 2f, 0f, 2f, 4f, 5f, 5f, 5f),
                reverbPreset = 3, // Large room
                bassBoost = 400,
                virtualizer = 400
            ),
            "Jazz" to AudioPreset(
                name = "Jazz",
                description = "Warm and balanced for jazz",
                eqBands = floatArrayOf(4f, 3f, 2f, 1f, 0f, 0f, 0f, 1f, 2f, 3f),
                reverbPreset = 2, // Plate
                bassBoost = 200,
                virtualizer = 500
            ),
            "Electronic" to AudioPreset(
                name = "Electronic",
                description = "Dynamic range for electronic music",
                eqBands = floatArrayOf(6f, 5f, 4f, 0f, -1f, 0f, 3f, 5f, 6f, 7f),
                reverbPreset = 0,
                bassBoost = 600,
                virtualizer = 700
            ),
            "Hip-Hop" to AudioPreset(
                name = "Hip-Hop",
                description = "Heavy bass with clear vocals",
                eqBands = floatArrayOf(7f, 6f, 5f, 2f, 0f, 1f, 2f, 3f, 3f, 3f),
                reverbPreset = 0,
                bassBoost = 900,
                virtualizer = 400
            ),
            "Acoustic" to AudioPreset(
                name = "Acoustic",
                description = "Natural sound for acoustic instruments",
                eqBands = floatArrayOf(3f, 2f, 1f, 0f, 1f, 2f, 2f, 2f, 1f, 0f),
                reverbPreset = 1, // Small room
                bassBoost = 100,
                virtualizer = 300
            ),
            "Treble Boost" to AudioPreset(
                name = "Treble Boost",
                description = "Enhanced high frequencies for clarity",
                eqBands = floatArrayOf(-2f, -2f, -1f, 0f, 1f, 2f, 4f, 6f, 7f, 8f),
                reverbPreset = 0,
                bassBoost = 0,
                virtualizer = 400
            ),
            "Flat" to AudioPreset(
                name = "Flat",
                description = "No modifications, pure audio",
                eqBands = floatArrayOf(0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f),
                reverbPreset = 0,
                bassBoost = 0,
                virtualizer = 0
            )
        )
    }
    
    /**
     * Analyze audio file and suggest optimal preset
     */
    suspend fun analyzeAndSuggestPreset(audioPath: String): AudioPreset? = withContext(Dispatchers.IO) {
        try {
            val characteristics = analyzeAudioCharacteristics(audioPath)
            val suggestedPresetName = determineOptimalPreset(characteristics)
            PRESETS[suggestedPresetName]
        } catch (e: Exception) {
            Log.e(TAG, "Error analyzing audio", e)
            PRESETS["Flat"]
        }
    }
    
    /**
     * Analyze audio characteristics using MediaMetadataRetriever
     */
    private fun analyzeAudioCharacteristics(audioPath: String): AudioCharacteristics {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(audioPath)
            
            // Extract metadata
            val genre = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_GENRE) ?: "Unknown"
            val bitrate = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toIntOrNull() ?: 0
            val sampleRate = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_SAMPLERATE)?.toIntOrNull() ?: 0
            
            // Estimate frequency characteristics based on genre and bitrate
            val bassLevel = estimateBassLevel(genre, bitrate)
            val midLevel = estimateMidLevel(genre)
            val trebleLevel = estimateTrebleLevel(genre, sampleRate)
            
            return AudioCharacteristics(
                genre = genre,
                bitrate = bitrate,
                sampleRate = sampleRate,
                bassLevel = bassLevel,
                midLevel = midLevel,
                trebleLevel = trebleLevel
            )
        } finally {
            retriever.release()
        }
    }
    
    /**
     * Determine optimal preset based on audio characteristics
     */
    private fun determineOptimalPreset(characteristics: AudioCharacteristics): String {
        val genre = characteristics.genre.lowercase()
        
        return when {
            genre.contains("rock") || genre.contains("metal") -> "Rock"
            genre.contains("jazz") || genre.contains("blues") -> "Jazz"
            genre.contains("classical") || genre.contains("orchestra") -> "Classical"
            genre.contains("electronic") || genre.contains("edm") || genre.contains("techno") -> "Electronic"
            genre.contains("hip") || genre.contains("rap") || genre.contains("trap") -> "Hip-Hop"
            genre.contains("acoustic") || genre.contains("folk") -> "Acoustic"
            genre.contains("pop") && characteristics.bassLevel > 0.6f -> "Bass Boost"
            genre.contains("vocal") || genre.contains("podcast") -> "Vocal Clarity"
            characteristics.bassLevel > 0.7f -> "Bass Boost"
            characteristics.trebleLevel > 0.7f -> "Treble Boost"
            else -> "Flat"
        }
    }
    
    private fun estimateBassLevel(genre: String, bitrate: Int): Float {
        val genreLower = genre.lowercase()
        return when {
            genreLower.contains("hip") || genreLower.contains("rap") || genreLower.contains("trap") -> 0.9f
            genreLower.contains("electronic") || genreLower.contains("edm") -> 0.8f
            genreLower.contains("rock") || genreLower.contains("metal") -> 0.7f
            genreLower.contains("jazz") || genreLower.contains("blues") -> 0.6f
            genreLower.contains("classical") -> 0.4f
            genreLower.contains("vocal") || genreLower.contains("acoustic") -> 0.3f
            else -> 0.5f
        }
    }
    
    private fun estimateMidLevel(genre: String): Float {
        val genreLower = genre.lowercase()
        return when {
            genreLower.contains("vocal") || genreLower.contains("podcast") -> 0.9f
            genreLower.contains("rock") || genreLower.contains("metal") -> 0.8f
            genreLower.contains("jazz") || genreLower.contains("acoustic") -> 0.7f
            else -> 0.6f
        }
    }
    
    private fun estimateTrebleLevel(genre: String, sampleRate: Int): Float {
        val genreLower = genre.lowercase()
        val sampleRateFactor = if (sampleRate > 44100) 0.1f else 0f
        
        val baseLevel = when {
            genreLower.contains("classical") || genreLower.contains("orchestra") -> 0.8f
            genreLower.contains("jazz") || genreLower.contains("acoustic") -> 0.7f
            genreLower.contains("electronic") || genreLower.contains("edm") -> 0.8f
            genreLower.contains("rock") || genreLower.contains("metal") -> 0.7f
            else -> 0.5f
        }
        
        return (baseLevel + sampleRateFactor).coerceIn(0f, 1f)
    }
    
    /**
     * Get all available presets
     */
    fun getAllPresets(): List<AudioPreset> = PRESETS.values.toList()
    
    /**
     * Get preset by name
     */
    fun getPreset(name: String): AudioPreset? = PRESETS[name]
}

/**
 * Data class representing audio characteristics
 */
data class AudioCharacteristics(
    val genre: String,
    val bitrate: Int,
    val sampleRate: Int,
    val bassLevel: Float,
    val midLevel: Float,
    val trebleLevel: Float
)

/**
 * Data class representing an audio preset
 */
data class AudioPreset(
    val name: String,
    val description: String,
    val eqBands: FloatArray, // 10-band EQ values in dB (-10 to +10)
    val reverbPreset: Int, // 0=None, 1=SmallRoom, 2=Plate, 3=LargeRoom, 4=ConcertHall
    val bassBoost: Int, // 0-1000
    val virtualizer: Int // 0-1000
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false

        other as AudioPreset

        if (name != other.name) return false
        if (description != other.description) return false
        if (!eqBands.contentEquals(other.eqBands)) return false
        if (reverbPreset != other.reverbPreset) return false
        if (bassBoost != other.bassBoost) return false
        if (virtualizer != other.virtualizer) return false

        return true
    }

    override fun hashCode(): Int {
        var result = name.hashCode()
        result = 31 * result + description.hashCode()
        result = 31 * result + eqBands.contentHashCode()
        result = 31 * result + reverbPreset
        result = 31 * result + bassBoost
        result = 31 * result + virtualizer
        return result
    }
}
