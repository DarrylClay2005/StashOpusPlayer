package com.stash.opusplayer.metadata.domain

import androidx.room.*
import com.stash.opusplayer.data.Song
import kotlinx.coroutines.flow.Flow

/**
 * Revolutionary Metadata System with AI Enhancement
 * 
 * Comprehensive metadata with 40+ fields and AI-powered analysis
 */

@Entity(
    tableName = "revolutionary_metadata",
    indices = [
        Index(value = ["aiGenre"]),
        Index(value = ["aiMood"]),
        Index(value = ["aiEnergy"]),
        Index(value = ["title"]),
        Index(value = ["artist"])
    ]
)
data class RevolutionaryMetadata(
    @PrimaryKey val songId: Long,
    
    // Basic Metadata
    val title: String,
    val artist: String,
    val album: String,
    val albumArtist: String?,
    val composer: String?,
    val genre: String?,
    val year: Int?,
    val trackNumber: Int?,
    val trackCount: Int?,
    val discNumber: Int?,
    val discCount: Int?,
    val duration: Long,
    val bitrate: Int?,
    val sampleRate: Int?,
    val channels: Int?,
    
    // AI Analysis Results
    val aiGenre: String?,
    val aiMood: String?,
    val aiEnergy: Float?,
    val aiValence: Float?, // Positivity/negativity
    val aiArousal: Float?, // Intensity/calmness
    val aiDanceability: Float?,
    val aiAcousticness: Float?,
    val aiInstrumentalness: Float?,
    val aiLiveness: Float?,
    val aiSpeechiness: Float?,
    val aiTempo: Float?,
    val aiKey: String?,
    val aiMode: String?, // Major/minor
    val aiComplexity: Float?,
    val aiQualityScore: Float?,
    
    // Advanced Audio Analysis
    val spectralCentroid: Float?,
    val spectralRolloff: Float?,
    val zeroCrossingRate: Float?,
    val mfccFeatures: String?, // JSON array of MFCC coefficients
    val chromaFeatures: String?, // JSON array of chroma features
    val tonnetzFeatures: String?, // JSON array of tonnetz features
    
    // Metadata Enhancement
    val enhancedTitle: String?,
    val enhancedArtist: String?,
    val enhancedAlbum: String?,
    val enhancedGenre: String?,
    val artworkUrl: String?,
    val lyricsUrl: String?,
    val musicBrainzId: String?,
    val lastFmUrl: String?,
    
    // Processing Timestamps
    val createdAt: Long = System.currentTimeMillis(),
    val lastAnalyzed: Long = System.currentTimeMillis(),
    val analysisVersion: Int = 1,

    // Fingerprint for duplicate detection
    val fingerprint: String? = null
)

/**
 * DAO for Revolutionary Metadata
 */
@Dao
interface RevolutionaryMetadataDao {
    
    @Query("SELECT * FROM revolutionary_metadata WHERE songId = :songId")
    suspend fun getMetadata(songId: Long): RevolutionaryMetadata?
    
    @Query("SELECT * FROM revolutionary_metadata WHERE songId IN (:songIds)")
    suspend fun getMetadataForSongs(songIds: List<Long>): List<RevolutionaryMetadata>
    
    @Query("SELECT * FROM revolutionary_metadata")
    fun getAllMetadata(): Flow<List<RevolutionaryMetadata>>
    
    @Query("SELECT * FROM revolutionary_metadata WHERE aiGenre = :genre")
    suspend fun getSongsByAIGenre(genre: String): List<RevolutionaryMetadata>
    
    @Query("SELECT * FROM revolutionary_metadata WHERE aiMood = :mood")
    suspend fun getSongsByAIMood(mood: String): List<RevolutionaryMetadata>
    
    @Query("SELECT * FROM revolutionary_metadata WHERE aiEnergy BETWEEN :minEnergy AND :maxEnergy")
    suspend fun getSongsByEnergyRange(minEnergy: Float, maxEnergy: Float): List<RevolutionaryMetadata>
    
    @Query("SELECT * FROM revolutionary_metadata WHERE aiQualityScore >= :minQuality ORDER BY aiQualityScore DESC")
    suspend fun getHighQualitySongs(minQuality: Float): List<RevolutionaryMetadata>
    
    @Query("SELECT DISTINCT aiGenre FROM revolutionary_metadata WHERE aiGenre IS NOT NULL")
    suspend fun getAllAIGenres(): List<String>
    
    @Query("SELECT DISTINCT aiMood FROM revolutionary_metadata WHERE aiMood IS NOT NULL")
    suspend fun getAllAIMoods(): List<String>
    
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertMetadata(metadata: RevolutionaryMetadata)
    
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertMetadata(metadata: List<RevolutionaryMetadata>)
    
    @Update
    suspend fun updateMetadata(metadata: RevolutionaryMetadata)
    
    @Delete
    suspend fun deleteMetadata(metadata: RevolutionaryMetadata)
    
    @Query("DELETE FROM revolutionary_metadata WHERE songId = :songId")
    suspend fun deleteMetadataForSong(songId: Long)
    
    @Query("DELETE FROM revolutionary_metadata WHERE songId IN (:songIds)")
    suspend fun deleteMetadataForSongs(songIds: List<Long>)
    
    @Query("SELECT COUNT(*) FROM revolutionary_metadata")
    suspend fun getMetadataCount(): Int
    
    @Query("SELECT COUNT(*) FROM revolutionary_metadata WHERE aiGenre IS NOT NULL")
    suspend fun getAnalyzedCount(): Int
    
    @Query("SELECT songId FROM revolutionary_metadata WHERE lastAnalyzed < :timestamp")
    suspend fun getSongsNeedingReanalysis(timestamp: Long): List<Long>
}

/**
 * Repository for Revolutionary Metadata
 */
class RevolutionaryMetadataRepository(
    private val metadataDao: RevolutionaryMetadataDao
) {
    
    suspend fun getMetadata(songId: Long): RevolutionaryMetadata? {
        return metadataDao.getMetadata(songId)
    }
    
    suspend fun getMetadataForSongs(songIds: List<Long>): List<RevolutionaryMetadata> {
        return metadataDao.getMetadataForSongs(songIds)
    }
    
    fun getAllMetadata(): Flow<List<RevolutionaryMetadata>> {
        return metadataDao.getAllMetadata()
    }
    
    suspend fun insertOrUpdateMetadata(metadata: RevolutionaryMetadata) {
        metadataDao.insertMetadata(metadata)
    }
    
    suspend fun insertOrUpdateMetadata(metadata: List<RevolutionaryMetadata>) {
        metadataDao.insertMetadata(metadata)
    }
    
    suspend fun getSongsByGenre(genre: String): List<RevolutionaryMetadata> {
        return metadataDao.getSongsByAIGenre(genre)
    }
    
    suspend fun getSongsByMood(mood: String): List<RevolutionaryMetadata> {
        return metadataDao.getSongsByAIMood(mood)
    }
    
    suspend fun getSongsByEnergyLevel(minEnergy: Float, maxEnergy: Float): List<RevolutionaryMetadata> {
        return metadataDao.getSongsByEnergyRange(minEnergy, maxEnergy)
    }
    
    suspend fun getHighQualitySongs(minQuality: Float = 0.7f): List<RevolutionaryMetadata> {
        return metadataDao.getHighQualitySongs(minQuality)
    }
    
    suspend fun getAllGenres(): List<String> {
        return metadataDao.getAllAIGenres()
    }
    
    suspend fun getAllMoods(): List<String> {
        return metadataDao.getAllAIMoods()
    }
    
    suspend fun getAnalysisStats(): AnalysisStats {
        val total = metadataDao.getMetadataCount()
        val analyzed = metadataDao.getAnalyzedCount()
        return AnalysisStats(total, analyzed, (analyzed.toFloat() / total.toFloat() * 100).toInt())
    }
    
    suspend fun getSongsNeedingReanalysis(olderThanDays: Int = 30): List<Long> {
        val timestamp = System.currentTimeMillis() - (olderThanDays * 24 * 60 * 60 * 1000L)
        return metadataDao.getSongsNeedingReanalysis(timestamp)
    }
    
    suspend fun deleteMetadata(songId: Long) {
        metadataDao.deleteMetadataForSong(songId)
    }
}

/**
 * Analysis Statistics
 */
data class AnalysisStats(
    val totalSongs: Int,
    val analyzedSongs: Int,
    val completionPercentage: Int
)

/**
 * AI Analysis Results
 */
data class AIAnalysisResult(
    val genre: String?,
    val mood: String?,
    val energy: Float?,
    val valence: Float?,
    val arousal: Float?,
    val danceability: Float?,
    val acousticness: Float?,
    val instrumentalness: Float?,
    val liveness: Float?,
    val speechiness: Float?,
    val tempo: Float?,
    val key: String?,
    val mode: String?,
    val complexity: Float?,
    val qualityScore: Float?,
    val spectralFeatures: SpectralFeatures?,
    val confidence: Float = 0.0f
)

/**
 * Spectral Features from Audio Analysis
 */
data class SpectralFeatures(
    val spectralCentroid: Float,
    val spectralRolloff: Float,
    val zeroCrossingRate: Float,
    val mfccFeatures: FloatArray,
    val chromaFeatures: FloatArray,
    val tonnetzFeatures: FloatArray
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false

        other as SpectralFeatures

        if (spectralCentroid != other.spectralCentroid) return false
        if (spectralRolloff != other.spectralRolloff) return false
        if (zeroCrossingRate != other.zeroCrossingRate) return false
        if (!mfccFeatures.contentEquals(other.mfccFeatures)) return false
        if (!chromaFeatures.contentEquals(other.chromaFeatures)) return false
        if (!tonnetzFeatures.contentEquals(other.tonnetzFeatures)) return false

        return true
    }

    override fun hashCode(): Int {
        var result = spectralCentroid.hashCode()
        result = 31 * result + spectralRolloff.hashCode()
        result = 31 * result + zeroCrossingRate.hashCode()
        result = 31 * result + mfccFeatures.contentHashCode()
        result = 31 * result + chromaFeatures.contentHashCode()
        result = 31 * result + tonnetzFeatures.contentHashCode()
        return result
    }
}