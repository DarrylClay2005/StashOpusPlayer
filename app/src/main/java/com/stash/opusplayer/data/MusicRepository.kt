package com.stash.opusplayer.data

import android.content.Context
import android.content.SharedPreferences
import android.database.Cursor
import android.net.Uri
import android.provider.MediaStore
import androidx.preference.PreferenceManager
import com.stash.opusplayer.data.database.FavoriteEntity
import com.stash.opusplayer.data.database.MusicDatabase
import com.stash.opusplayer.data.database.PlaylistDao
import com.stash.opusplayer.data.database.PlaylistEntity
import com.stash.opusplayer.data.database.PlaylistTrackEntity
import com.stash.opusplayer.data.database.PlaylistWithCount
import com.stash.opusplayer.utils.MetadataExtractor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
import java.io.File

class MusicRepository(private val context: Context) {
    
    private val aiTagger = com.stash.opusplayer.ai.AITagger(context)
    
    private val database = MusicDatabase.getDatabase(context)
    private val favoriteDao = database.favoriteDao()
    private val playlistDao: PlaylistDao = database.playlistDao()
    private val metadataExtractor = MetadataExtractor(context)
    private val prefs: SharedPreferences = PreferenceManager.getDefaultSharedPreferences(context)
    
    // Playlists API
    fun getPlaylists(): Flow<List<PlaylistWithCount>> = playlistDao.getPlaylistsWithCount()

    suspend fun createPlaylist(name: String): Long = withContext(Dispatchers.IO) {
        playlistDao.insertPlaylist(PlaylistEntity(name = name))
    }

    suspend fun deletePlaylist(playlistId: Long) = withContext(Dispatchers.IO) {
        playlistDao.deletePlaylist(playlistId)
    }

    fun getPlaylistTracks(playlistId: Long): Flow<List<PlaylistTrackEntity>> = playlistDao.getTracks(playlistId)

    suspend fun addSongToPlaylist(playlistId: Long, song: Song) = withContext(Dispatchers.IO) {
        val track = PlaylistTrackEntity(
            playlistId = playlistId,
            songId = song.id,
            title = song.displayName,
            artist = song.artistName,
            album = song.albumName,
            duration = song.duration,
            path = song.path
        )
        playlistDao.insertTrack(track)
    }

    suspend fun removeSongFromPlaylist(playlistId: Long, songId: Long) = withContext(Dispatchers.IO) {
        playlistDao.deleteTrackByPlaylistAndSong(playlistId, songId)
    }

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
            MediaStore.Audio.Media.MIME_TYPE,
            MediaStore.Audio.Media.RELATIVE_PATH
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
    
    private fun Cursor.safeString(column: String, default: String = ""): String {
        val idx = getColumnIndex(column)
        return if (idx != -1) getString(idx) ?: default else default
    }

    private fun Cursor.safeLong(column: String, default: Long = 0L): Long {
        val idx = getColumnIndex(column)
        return if (idx != -1) runCatching { getLong(idx) }.getOrNull() ?: default else default
    }

    private fun createSongFromCursorCompat(cursor: Cursor): Song? {
        return try {
            val id = cursor.safeLong(MediaStore.Audio.Media._ID)
            if (id <= 0) return null
            val title = cursor.safeString(MediaStore.Audio.Media.TITLE)
            val artist = cursor.safeString(MediaStore.Audio.Media.ARTIST)
            val album = cursor.safeString(MediaStore.Audio.Media.ALBUM)
            val duration = cursor.safeLong(MediaStore.Audio.Media.DURATION)
            
            // DATA may be unavailable on Android 10+, fall back to content Uri string
            val dataIndex = cursor.getColumnIndex(MediaStore.Audio.Media.DATA)
            val path = if (dataIndex != -1) {
                cursor.getString(dataIndex) ?: ""
            } else {
                android.content.ContentUris.withAppendedId(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id
                ).toString()
            }
            
            val albumId = cursor.safeLong(MediaStore.Audio.Media.ALBUM_ID, -1)
            val artistId = cursor.safeLong(MediaStore.Audio.Media.ARTIST_ID, -1)
            val dateAdded = cursor.safeLong(MediaStore.Audio.Media.DATE_ADDED)
            val size = cursor.safeLong(MediaStore.Audio.Media.SIZE)
            val mimeType = cursor.safeString(MediaStore.Audio.Media.MIME_TYPE)
            val relativePath = cursor.safeString(MediaStore.Audio.Media.RELATIVE_PATH)
            
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
                mimeType = mimeType,
                relativePath = relativePath
            )
        } catch (_: Exception) {
            null
        }
    }
    
private fun isValidAudioFile(path: String): Boolean {
        if (path.startsWith("content://")) {
            // Allow all content URIs; filtering is done by retriever and decoding later
            return true
        }
        val extension = path.substringAfterLast(".", "").lowercase()
        // Accept common audio file extensions, especially .opus
        return extension in setOf("mp3", "opus", "ogg", "oga", "flac", "m4a", "aac", "wav", "wma", "mka")
    }
    
    // Enhanced method to get all songs with metadata and favorites status
suspend fun getAllSongsWithMetadata(): List<Song> = withContext(Dispatchers.IO) {
        com.stash.opusplayer.utils.LibraryScanTracker.update("Scanning MediaStore…")
        val baseSongs = getAllSongs()
        // For now, we'll just return songs without favorite status since Flow handling is complex
        // This will be enhanced in future updates
        val favoriteIds = emptySet<Long>()
        
baseSongs.map { song ->
            val enhancedSong = metadataExtractor.extractMetadata(song)
            val withFav = enhancedSong.copy(isFavorite = favoriteIds.contains(song.id))
            aiTagger.enhanceSong(withFav)
        }
    }
    
    // Scan custom folders for music files
suspend fun scanCustomFolders(): List<Song> = withContext(Dispatchers.IO) {
        com.stash.opusplayer.utils.LibraryScanTracker.update("Scanning custom folders…")
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

    // AI-ish genre inference using tags or heuristics; placeholder for external APIs
    suspend fun getSongsByGenreSmart(): Map<String, List<Song>> = withContext(Dispatchers.IO) {
        val all = getAllSongsWithMetadata()
        val normalized = all.map { s ->
            val g = s.genre.trim()
            if (g.isNotEmpty()) {
                s.copy(genre = g)
            } else {
                // Simple heuristic: infer from file path or album keywords
                val inferred = inferGenreFromHeuristics(s)
                s.copy(genre = inferred)
            }
        }
        normalized.groupBy { it.genre.ifBlank { "Unknown" } }
    }

    private fun inferGenreFromHeuristics(s: Song): String {
        val haystack = (s.albumName + " " + s.displayName + " " + s.path).lowercase()
        return when {
            listOf("live", "unplugged").any { haystack.contains(it) } -> "Live"
            listOf("remix", "mix", "club").any { haystack.contains(it) } -> "Dance"
            listOf("lofi", "chill").any { haystack.contains(it) } -> "Lo-Fi"
            listOf("metal", "hardcore").any { haystack.contains(it) } -> "Metal"
            listOf("hip hop", "rap").any { haystack.contains(it) } -> "Hip-Hop"
            listOf("jazz").any { haystack.contains(it) } -> "Jazz"
            listOf("classical", "symphony", "concerto").any { haystack.contains(it) } -> "Classical"
            else -> "Unknown"
        }
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

    fun addCustomMusicFolderTreeUri(treeUri: String) {
        val existing = prefs.getStringSet("custom_music_folders_tree", setOf())?.toMutableSet() ?: mutableSetOf()
        existing.add(treeUri)
        prefs.edit().putStringSet("custom_music_folders_tree", existing).apply()
    }

    fun getCustomMusicFolderTreeUris(): Set<String> {
        return prefs.getStringSet("custom_music_folders_tree", setOf()) ?: setOf()
    }

    // Combined method to get all songs from both MediaStore and custom folders
suspend fun getAllSongsFromAllSources(): List<Song> = withContext(Dispatchers.IO) {
        com.stash.opusplayer.utils.LibraryScanTracker.update("Scanning your library…")
        val mediaStoreSongs = getAllSongsWithMetadata()
        val diskFolderSongs = scanCustomFolders()
        val treeSongs = scanDocumentTrees()
        
val combined = (mediaStoreSongs + diskFolderSongs + treeSongs)
            .distinctBy { it.path }
        com.stash.opusplayer.utils.LibraryScanTracker.update("AI tagging songs…")
        val tagged = aiTagger.enhanceSongs(combined)
        com.stash.opusplayer.utils.LibraryScanTracker.update("Finalizing…")
        tagged.sortedBy { it.displayName }
    }

private suspend fun scanDocumentTrees(): List<Song> = withContext(Dispatchers.IO) {
        com.stash.opusplayer.utils.LibraryScanTracker.update("Scanning added folders…")
        val result = mutableListOf<Song>()
        val trees = getCustomMusicFolderTreeUris()
        for (uriStr in trees) {
            try {
                val treeUri = android.net.Uri.parse(uriStr)
                val docTree = androidx.documentfile.provider.DocumentFile.fromTreeUri(context, treeUri)
                if (docTree != null && docTree.isDirectory) {
                    val rootLabel = docTree.name ?: "Music"
                    scanDocumentTreeRecursive(docTree, result, rootLabel, rootLabel)
                }
            } catch (_: Exception) { }
        }
        result
    }

    private fun scanDocumentTreeRecursive(
        dir: androidx.documentfile.provider.DocumentFile,
        out: MutableList<Song>,
        rootLabel: String,
        currentPath: String
    ) {
        val children = dir.listFiles()
        for (child in children) {
            if (child.isDirectory) {
                val childName = child.name ?: "Folder"
                scanDocumentTreeRecursive(child, out, rootLabel, "$currentPath/$childName")
            } else if (child.isFile) {
                val name = child.name ?: continue
if (isValidAudioFile(name) || child.type?.startsWith("audio/") == true) {
                    val uriStr = child.uri.toString()
                    metadataExtractor.extractBasicInfo(uriStr)?.let { base ->
                        val withMeta = metadataExtractor.extractMetadata(base)
                        val adjusted = withMeta.copy(
                            relativePath = "$currentPath/"
                        )
                        out.add(adjusted)
                    }
                }
            }
        }
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
