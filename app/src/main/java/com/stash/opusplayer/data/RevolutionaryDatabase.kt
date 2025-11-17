package com.stash.opusplayer.data

import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import android.content.Context
import com.stash.opusplayer.metadata.domain.RevolutionaryMetadata
import com.stash.opusplayer.metadata.domain.RevolutionaryMetadataDao

/**
 * Revolutionary Database with Room
 * 
 * Comprehensive database schema with all revolutionary features
 */
@Database(
    entities = [
        RevolutionaryMetadata::class
    ],
    version = 4,
    exportSchema = false // Disable for now to avoid build issues
)
@TypeConverters(Converters::class)
abstract class RevolutionaryDatabase : RoomDatabase() {
    
    abstract fun metadataDao(): RevolutionaryMetadataDao
    
    companion object {
        @Volatile
        private var INSTANCE: RevolutionaryDatabase? = null
        
        fun getDatabase(context: Context): RevolutionaryDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    RevolutionaryDatabase::class.java,
                    "revolutionary_database"
                )
                    .addMigrations(MIGRATION_1_2, MIGRATION_2_3, MIGRATION_3_4)
                    .fallbackToDestructiveMigrationOnDowngrade()
                    .fallbackToDestructiveMigration()
                    .build()
                INSTANCE = instance
                instance
            }
        }
        
        val MIGRATION_1_2 = object : androidx.room.migration.Migration(1, 2) {
            override fun migrate(database: androidx.sqlite.db.SupportSQLiteDatabase) {
                // No schema changes; placeholder migration to enable future evolution without destructive drops
            }
        }
        val MIGRATION_2_3 = object : androidx.room.migration.Migration(2, 3) {
            override fun migrate(database: androidx.sqlite.db.SupportSQLiteDatabase) {
                // Add indices to accelerate AI queries
                runCatching { database.execSQL("CREATE INDEX IF NOT EXISTS index_revolutionary_metadata_aiGenre ON revolutionary_metadata(aiGenre)") }
                runCatching { database.execSQL("CREATE INDEX IF NOT EXISTS index_revolutionary_metadata_aiMood ON revolutionary_metadata(aiMood)") }
                runCatching { database.execSQL("CREATE INDEX IF NOT EXISTS index_revolutionary_metadata_aiEnergy ON revolutionary_metadata(aiEnergy)") }
                runCatching { database.execSQL("CREATE INDEX IF NOT EXISTS index_revolutionary_metadata_title ON revolutionary_metadata(title)") }
                runCatching { database.execSQL("CREATE INDEX IF NOT EXISTS index_revolutionary_metadata_artist ON revolutionary_metadata(artist)") }
            }
        }
        val MIGRATION_3_4 = object : androidx.room.migration.Migration(3, 4) {
            override fun migrate(database: androidx.sqlite.db.SupportSQLiteDatabase) {
                runCatching { database.execSQL("ALTER TABLE revolutionary_metadata ADD COLUMN fingerprint TEXT") }
            }
        }
    }
}

/**
 * Type converters for Room database
 */
class Converters {
    @androidx.room.TypeConverter
    fun fromStringList(value: List<String>?): String {
        return value?.joinToString(",") ?: ""
    }
    
    @androidx.room.TypeConverter
    fun toStringList(value: String?): List<String> {
        return value?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
    }
}
