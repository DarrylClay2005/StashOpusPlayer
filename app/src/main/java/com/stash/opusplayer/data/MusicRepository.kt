package com.stash.opusplayer.data

import android.content.Context
import android.content.SharedPreferences
import android.database.Cursor
import android.net.Uri
import android.provider.MediaStore
import androidx.preference.PreferenceManager
import com.stash.opusplayer.data.database.FavoriteEntity
import com.stash.opusplayer.data.database.MusicDatabase
import com.stash.opusplayer.utils.MetadataExtractor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
import java.io.File

class MusicRepository(private val context: Context) {
    
    private val database = MusicDatabase.getDatabase(context)
    private val favoriteDao = database.favoriteDao()
    private val metadataExtractor = MetadataExtractor(context)
    private val prefs: SharedPreferences = PreferenceManager.getDefaultSharedPreferences(context)
    
    suspend fun getAllSongs(): List<Song> = withContext(Dispatchers.IO) {
        val songs = mutableListOf<Song>()
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0"
        val sortOrder = "${MediaStore.Audio.Media.DISPLAY_NAME} ASC"
        
        // Use a projection compatible with scoped storage on Android 10+
        val projection = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.ARTIST_ID,
            MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.SIZE,
            MediaStore.Audio.Media.MIME_TYPE
        ) else PROJECTION
        
        try {
            val cursor = context.contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                null,
                sortOrder
            )
            
            cursor?.use {
                while (it.moveToNext()) {
                    val song = createSongFromCursorCompat(it)
                    if (song != null && isValidAudioFile(song.path)) {
                        songs.add(song)
                    }
                }
            }
        } catch (_: SecurityException) {
            // Permission issue: return empty list gracefully
        } catch (_: Exception) {
            // Any other resolver error: return what we have so far
        }
        
        songs
    }
    
    private fun createSongFromCursorCompat(cursor: Cursor): Song? {
        return try {
            val id = cursor.getLong(cursor.getColumnIndex(MediaStore.Audio.Media._ID).coerceAtLeast(0))
            val title = cursor.getString(cursor.getColumnIndex(MediaStore.Audio.Media.TITLE).coerceAtLeast(0)) ?: ""
            val artist = cursor.getString(cursor.getColumnIndex(MediaStore.Audio.Media.ARTIST).coerceAtLeast(0)) ?: ""
            val album = cursor.getString(cursor.getColumnIndex(MediaStore.Audio.Media.ALBUM).coerceAtLeast(0)) ?: ""
            val duration = cursor.getLong(cursor.getColumnIndex(MediaStore.Audio.Media.DURATION).coerceAtLeast(0))
            
            // DATA may be unavailable on Android 10+, fall back to content Uri string
            val dataIndex = cursor.getColumnIndex(MediaStore.Audio.Media.DATA)
            val path = if (dataIndex != -1) {
                cursor.getString(dataIndex) ?: ""
            } else {
                android.content.ContentUris.withAppendedId(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id
                ).toString()
            }
            
            val albumId = cursor.getLong(cursor.getColumnIndex(MediaStore.Audio.Media.ALBUM_ID).coerceAtLeast(0))
            val artistId = cursor.getLong(cursor.getColumnIndex(MediaStore.Audio.Media.ARTIST_ID).coerceAtLeast(0))
            val dateAdded = cursor.getLong(cursor.getColumnIndex(MediaStore.Audio.Media.DATE_ADDED).coerceAtLeast(0))
            val size = cursor.getLong(cursor.getColumnIndex(MediaStore.Audio.Media.SIZE).coerceAtLeast(0))
            val mimeType = cursor.getString(cursor.getColumnIndex(MediaStore.Audio.Media.MIME_TYPE).coerceAtLeast(0)) ?: ""
            
            Song(
                id = id,
                title = title,
                artist = artist,
                album = album,
                duration = duration,
                path = path,
                albumId = albumId,
                artistId = artistId,
                dateAdded = dateAdded,
                size = size,
                mimeType = mimeType
            )
        } catch (_: Exception) {
            null
        }
    }
    
    private fun isValidAudioFile(path: String): Boolean {
        if (path.startsWith("content://")) return true // content URIs are valid
        val supportedExtensions = listOf("mp3", "opus", "ogg", "flac", "m4a", "wav", "aac", "wma")
        val extension = path.substringAfterLast(".", "").lowercase()
        return supportedExtensions.contains(extension)
    }
    
    // Enhanced method to get all songs with metadata and favorites status
    suspend fun getAllSongsWithMetadata(): List<Song> = withContext(Dispatchers.IO) {
        val baseSongs = getAllSongs()
        // For now, we'll just return songs without favorite status since Flow handling is complex
        // This will be enhanced in future updates
        val favoriteIds = emptySet<Long>()
        
        baseSongs.map { song ->
            val enhancedSong = metadataExtractor.extractMetadata(song)
            enhancedSong.copy(isFavorite = favoriteIds.contains(song.id))
        }
    }
    
    // Scan custom folders for music files
    suspend fun scanCustomFolders(): List<Song> = withContext(Dispatchers.IO) {
        val customFolders = getCustomMusicFolders()
        val songs = mutableListOf<Song>()
        
        customFolders.forEach { folderPath ->
            songs.addAll(scanFolderRecursively(folderPath))
        }
        
        songs.distinctBy { it.path } // Remove duplicates
    }
    
    private suspend fun scanFolderRecursively(folderPath: String): List<Song> {
        val songs = mutableListOf<Song>()
        val folder = File(folderPath)
        
        if (!folder.exists() || !folder.isDirectory) return songs
        
        try {
            folder.listFiles()?.forEach { file ->
                when {
                    file.isDirectory -> {
                        // Recursively scan subfolders
                        songs.addAll(scanFolderRecursively(file.absolutePath))
                    }
                    file.isFile && isValidAudioFile(file.absolutePath) -> {
                        metadataExtractor.extractBasicInfo(file.absolutePath)?.let { song ->
                            songs.add(metadataExtractor.extractMetadata(song))
                        }
                    }
                }
            }
        } catch (e: Exception) {
            // Log error but continue scanning
        }
        
        return songs
    }
    
    // Favorites management
    suspend fun addToFavorites(song: Song) {
        val favorite = FavoriteEntity(
            songId = song.id,
            title = song.displayName,
            artist = song.artistName,
            album = song.albumName,
            path = song.path
        )
        favoriteDao.insertFavorite(favorite)
    }
    
    suspend fun removeFromFavorites(songId: Long) {
        favoriteDao.deleteFavoriteById(songId)
    }
    
    suspend fun isFavorite(songId: Long): Boolean {
        return favoriteDao.isFavorite(songId)
    }
    
    fun getFavorites(): Flow<List<Song>> {
        return favoriteDao.getAllFavorites().map { favorites ->
            favorites.mapNotNull { favorite ->
                // Convert FavoriteEntity back to Song
                val file = File(favorite.path)
                if (file.exists()) {
                    Song(
                        id = favorite.songId,
                        title = favorite.title,
                        artist = favorite.artist,
                        album = favorite.album,
                        duration = 0, // Will be filled by metadata extractor
                        path = favorite.path,
                        isFavorite = true
                    )
                } else null
            }
        }
    }
    
    // Artist/Producer organization
    suspend fun getSongsByArtist(): Map<String, List<Song>> = withContext(Dispatchers.IO) {
        val allSongs = getAllSongsWithMetadata()
        allSongs.groupBy { it.artistName }
    }
    
    suspend fun getArtists(): List<String> = withContext(Dispatchers.IO) {
        val allSongs = getAllSongsWithMetadata()
        allSongs.map { it.artistName }.distinct().sorted()
    }
    
    suspend fun getSongsByArtist(artist: String): List<Song> = withContext(Dispatchers.IO) {
        val allSongs = getAllSongsWithMetadata()
        allSongs.filter { it.artistName == artist }
    }
    
    // Album organization
    suspend fun getSongsByAlbum(): Map<String, List<Song>> = withContext(Dispatchers.IO) {
        val allSongs = getAllSongsWithMetadata()
        allSongs.groupBy { it.albumName }
    }
    
    suspend fun getAlbums(): List<String> = withContext(Dispatchers.IO) {
        val allSongs = getAllSongsWithMetadata()
        allSongs.map { it.albumName }.distinct().sorted()
    }
    
    // Folder management
    fun addCustomMusicFolder(folderPath: String) {
        val existingFolders = getCustomMusicFolders().toMutableSet()
        existingFolders.add(folderPath)
        prefs.edit().putStringSet("custom_music_folders", existingFolders).apply()
    }
    
    fun removeCustomMusicFolder(folderPath: String) {
        val existingFolders = getCustomMusicFolders().toMutableSet()
        existingFolders.remove(folderPath)
        prefs.edit().putStringSet("custom_music_folders", existingFolders).apply()
    }
    
    fun getCustomMusicFolders(): Set<String> {
        return prefs.getStringSet("custom_music_folders", setOf()) ?: setOf()
    }
    
    // Combined method to get all songs from both MediaStore and custom folders
    suspend fun getAllSongsFromAllSources(): List<Song> = withContext(Dispatchers.IO) {
        val mediaStoreSongs = getAllSongsWithMetadata()
        val customFolderSongs = scanCustomFolders()
        
        (mediaStoreSongs + customFolderSongs)
            .distinctBy { it.path } // Remove duplicates based on file path
            .sortedBy { it.displayName }
    }
    
    companion object {
        private val PROJECTION = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.ARTIST_ID,
            MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.SIZE,
            MediaStore.Audio.Media.MIME_TYPE
        )
    }
}
