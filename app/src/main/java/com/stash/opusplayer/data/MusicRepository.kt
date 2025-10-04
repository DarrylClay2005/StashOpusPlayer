package com.stash.stashwave.data

import android.content.Context
import android.content.SharedPreferences
import android.database.Cursor
import android.net.Uri
import android.provider.MediaStore
import androidx.preference.PreferenceManager
import com.stash.stashwave.data.database.FavoriteEntity
import com.stash.stashwave.data.database.MusicDatabase
import com.stash.stashwave.data.database.PlaylistDao
import com.stash.stashwave.data.database.PlaylistEntity
import com.stash.stashwave.data.database.PlaylistTrackEntity
import com.stash.stashwave.data.database.PlaylistWithCount
import com.stash.stashwave.utils.MetadataExtractor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
import java.io.File

class MusicRepository(private val context: Context) {
    
private val aiTagger = com.stash.stashwave.ai.AITagger(context)
    
    private val database = MusicDatabase.getDatabase(context)
    private val favoriteDao = database.favoriteDao()
    private val playlistDao: PlaylistDao = database.playlistDao()
    val metadataDao = database.metadataDao()
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
        // Accept all common audio file extensions
        return extension in setOf(
            "mp3", "opus", "ogg", "oga", "flac", "m4a", "aac", "wav", "wma", "mka",
            "mp4", "3gp", "webm", "mkv", "wv", "ape", "mpc", "ac3", "dts", "tta",
            "ra", "rm", "amr", "awb", "au", "snd", "aiff", "aifc", "caf", "mp2",
            "m4p", "m4b", "3g2", "asf", "wma", "wmv"
        )
    }
    
    // Enhanced method to get all songs with metadata and favorites status
suspend fun getAllSongsWithMetadata(): List<Song> = withContext(Dispatchers.IO) {
        if (com.stash.stashwave.utils.LibraryScanTracker.isScanInProgress()) {
            return@withContext emptyList()
        }
        
        try {
            com.stash.stashwave.utils.LibraryScanTracker.startScan("Scanning MediaStore…")
            val baseSongs = getAllSongs()
            // For now, we'll just return songs without favorite status since Flow handling is complex
            // This will be enhanced in future updates
            val favoriteIds = emptySet<Long>()
            
            baseSongs.map { song ->
                val enhancedSong = metadataExtractor.extractMetadata(song)
                val withFav = enhancedSong.copy(isFavorite = favoriteIds.contains(song.id))
                aiTagger.enhanceSong(withFav)
            }
        } finally {
            com.stash.stashwave.utils.LibraryScanTracker.completeScan()
        }
    }
    
    // Silent version for background metadata scanning - does not trigger LibraryScanTracker notifications
    suspend fun getAllSongsWithMetadataSilent(): List<Song> = withContext(Dispatchers.IO) {
        val baseSongs = getAllSongs()
        val favoriteIds = emptySet<Long>()
        
        baseSongs.map { song ->
            val enhancedSong = metadataExtractor.extractMetadata(song)
            val withFav = enhancedSong.copy(isFavorite = favoriteIds.contains(song.id))
            // Skip AI tagger for background scanning to improve performance
            withFav
        }
    }
    
    // Scan custom folders for music files
suspend fun scanCustomFolders(): List<Song> = withContext(Dispatchers.IO) {
        if (com.stash.stashwave.utils.LibraryScanTracker.isScanInProgress()) {
            return@withContext emptyList()
        }
        
        try {
            com.stash.stashwave.utils.LibraryScanTracker.startScan("Scanning custom folders…")
            val customFolders = getCustomMusicFolders()
            val songs = mutableListOf<Song>()
            
            customFolders.forEach { folderPath ->
                songs.addAll(scanFolderRecursively(folderPath))
            }
            
            songs.distinctBy { it.path } // Remove duplicates
        } finally {
            com.stash.stashwave.utils.LibraryScanTracker.completeScan()
        }
    }
    
    private suspend fun scanFolderRecursively(folderPath: String): List<Song> {
        return scanFolderRecursivelyFast(folderPath)
    }

    suspend fun getSongsInFolder(folderPath: String): List<Song> = scanFolderRecursivelyFast(folderPath)

    // Fast disk scan: avoids heavy metadata until later, filters by extension
    private suspend fun scanFolderRecursivelyFast(folderPath: String): List<Song> = withContext(Dispatchers.IO) {
        val songs = mutableListOf<Song>()
        val folder = File(folderPath)
        if (!folder.exists() || !folder.isDirectory) return@withContext songs
        try {
            val list = folder.listFiles()
            if (list != null) {
                for (file in list) {
                    if (file.isDirectory) {
                        songs.addAll(scanFolderRecursivelyFast(file.absolutePath))
                    } else if (file.isFile && isValidAudioFile(file.absolutePath)) {
                        // Build minimal Song object without invoking retriever
                        val title = file.nameWithoutExtension
                        songs.add(
                            Song(
                                id = file.absolutePath.hashCode().toLong(),
                                title = title,
                                artist = "Unknown Artist",
                                album = file.parentFile?.name ?: "Unknown Album",
                                duration = 0L,
                                path = file.absolutePath,
                                size = file.length(),
                                mimeType = "audio/*",
                                dateAdded = file.lastModified()
                            )
                        )
                    }
                }
            }
        } catch (_: Exception) { }
        songs
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
                val path = favorite.path
                val isContent = path.startsWith("content://")
                val exists = if (isContent) true else File(path).exists()
                if (exists) {
                    Song(
                        id = favorite.songId,
                        title = favorite.title,
                        artist = favorite.artist,
                        album = favorite.album,
                        duration = 0, // Will be filled by metadata extractor
                        path = path,
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
        val prefs = PreferenceManager.getDefaultSharedPreferences(context)
        val youTube = com.stash.stashwave.network.YouTubeApiService(context)

        fun normalizeTitle(name: String): String {
            return name.lowercase()
                .replace(Regex("\\(.*?\\)"), "")
                .replace(Regex("\".*?\""), "")
                .replace("remastered", "")
                .replace("official video", "")
                .replace("official audio", "")
                .replace("lyrics", "")
                .replace("feat.", "")
                .replace("ft.", "")
                .replace(Regex("[^a-z0-9 ]"), " ")
                .replace(Regex("\\s+"), " ")
                .trim()
        }

        fun inferFromText(text: String): String? {
            val t = text.lowercase()
            val mapping = listOf(
                "hip hop" to "Hip-Hop", "hip-hop" to "Hip-Hop", "rap" to "Hip-Hop",
                "r&b" to "R&B", "rnb" to "R&B",
                "pop" to "Pop",
                "rock" to "Rock",
                "metal" to "Metal",
                "jazz" to "Jazz",
                "classical" to "Classical", "symphony" to "Classical",
                "lofi" to "Lo-Fi", "lo-fi" to "Lo-Fi",
                "house" to "Electronic", "edm" to "Electronic", "electronic" to "Electronic",
                "trap" to "Hip-Hop", "drill" to "Hip-Hop",
                "indie" to "Indie",
                "country" to "Country",
                "blues" to "Blues",
                "reggae" to "Reggae",
                "afrobeat" to "Afrobeats", "afrobeats" to "Afrobeats"
            )
            return mapping.firstOrNull { t.contains(it.first) }?.second
        }

        val all = getAllSongsWithMetadata()
        val result = mutableMapOf<String, MutableList<Song>>()

        for (s in all) {
            // 1) Embedded or existing genre
            val g0 = s.genre.trim()
            var genre = if (g0.isNotBlank()) g0 else ""

            // 2) Infer from names
            if (genre.isBlank()) {
                genre = inferFromText("${s.displayName} ${s.albumName} ${s.artistName}") ?: ""
            }

            // 3) Cached value
            if (genre.isBlank()) {
                val key = "genre_cache_${stableKey(s)}"
                genre = prefs.getString(key, "") ?: ""
            }

            // 4) YouTube metadata lookup (best-effort)
            if (genre.isBlank()) {
                try {
                    val q = normalizeTitle("${s.displayName} ${s.artistName} genre")
                    val yt = youTube.searchVideos(q, maxResults = 1).getOrNull()
                    val vid = yt?.videos?.firstOrNull()
                    if (vid != null) {
                        genre = inferFromText("${vid.title} ${vid.description} ${vid.channelTitle}") ?: ""
                    }
                } catch (_: Exception) {}
            }

            if (genre.isBlank()) {
                val norm = normalizeTitle(s.displayName)
                genre = when {
                    norm.contains("mix") || norm.contains("remix") -> "Dance"
                    norm.contains("live") -> "Live"
                    else -> "Unknown"
                }
            }

            // Cache best-effort result
            runCatching {
                if (genre.isNotBlank() && genre != "Unknown") {
                    val key = "genre_cache_${stableKey(s)}"
                    prefs.edit().putString(key, genre).apply()
                }
            }

            result.getOrPut(genre) { mutableListOf() }.add(s)
        }

        // Sort songs in each genre by normalized title to group similar names
        return@withContext result.mapValues { (_, list) ->
            list.sortedWith(compareBy({ normalizeTitle(it.displayName) }, { it.displayName.lowercase() }))
        }
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

    // Fast combined scan (no heavy metadata/AI), for quick UI population
    suspend fun getAllSongsFromAllSourcesFast(): List<Song> = withContext(Dispatchers.IO) {
        val mediaStoreSongs = getAllSongs()
        val diskFolderSongs = scanCustomFolders()
        // Do not include treeSongs here; MediaStore query already covers them and caused duplicates in "All songs"
        val combined = mediaStoreSongs + diskFolderSongs
        val deduped = LinkedHashMap<String, Song>()
        for (s in combined) {
            val key = stableKey(s)
            if (!deduped.containsKey(key)) deduped[key] = s
        }
        deduped.values.sortedBy { it.displayName }
    }

    // Combined method to get all songs from both MediaStore and custom folders (full metadata + AI)
    suspend fun getAllSongsFromAllSources(): List<Song> = withContext(Dispatchers.IO) {
        if (com.stash.stashwave.utils.LibraryScanTracker.isScanInProgress()) {
            return@withContext emptyList()
        }
        
        try {
            com.stash.stashwave.utils.LibraryScanTracker.startScan("Scanning your library…")
            // Use fast scan first to avoid blocking
            val fast = getAllSongsFromAllSourcesFast()
            com.stash.stashwave.utils.LibraryScanTracker.update("Processing metadata…")
            // Then enrich each with metadata and AI
            val enriched = fast.map { s -> metadataExtractor.extractMetadata(s) }
            val ai = aiTagger.enhanceSongs(enriched)
            // Deduplicate using a stable key across sources (MediaStore vs file scans)
            val deduped = LinkedHashMap<String, Song>()
            for (s in ai) {
                val key = stableKey(s)
                if (!deduped.containsKey(key)) deduped[key] = s
            }
            com.stash.stashwave.utils.LibraryScanTracker.update("Finalizing…")
            deduped.values.sortedBy { it.displayName }
        } finally {
            com.stash.stashwave.utils.LibraryScanTracker.completeScan()
        }
    }
    
    // Silent version for background operations - does not trigger LibraryScanTracker notifications
    suspend fun getAllSongsFromAllSourcesSilent(): List<Song> = withContext(Dispatchers.IO) {
        // Use fast scan first to avoid blocking
        val fast = getAllSongsFromAllSourcesFast()
        // Then enrich each with metadata (skip AI for background performance)
        val enriched = fast.map { s -> metadataExtractor.extractMetadata(s) }
        // Deduplicate using a stable key across sources (MediaStore vs file scans)
        val deduped = LinkedHashMap<String, Song>()
        for (s in enriched) {
            val key = stableKey(s)
            if (!deduped.containsKey(key)) deduped[key] = s
        }
        deduped.values.sortedBy { it.displayName }
    }

private suspend fun scanDocumentTrees(): List<Song> = withContext(Dispatchers.IO) {
        com.stash.stashwave.utils.LibraryScanTracker.update("Scanning added folders…")
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
                        val adjusted = base.copy(
                            relativePath = "$currentPath/"
                        )
                        out.add(adjusted)
                    }
                }
            }
        }
    }

    // Fast path: use MediaStore to list audio under primary storage tree URIs
    private suspend fun scanDocumentTreesFast(): List<Song> = withContext(Dispatchers.IO) {
        val result = mutableListOf<Song>()
        val trees = getCustomMusicFolderTreeUris()
        for (uriStr in trees) {
            try {
                val treeUri = android.net.Uri.parse(uriStr)
                val docId = android.provider.DocumentsContract.getTreeDocumentId(treeUri)
                if (docId != null && (docId.startsWith("primary:") || docId.matches(Regex("[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}:.*")))) {
                    // Support both primary and removable storage UUID patterns
                    val rel = docId.substringAfter(":", "")
                    if (rel.isNotBlank()) {
                        val likeArg = "$rel/%"
                        val selection = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                            "${android.provider.MediaStore.Audio.Media.RELATIVE_PATH} LIKE ?"
                        } else {
                            // Pre-Q fallback: DATA contains full path; best-effort substring match
                            "${android.provider.MediaStore.Audio.Media.DATA} LIKE ?"
                        }
                        val args = arrayOf(likeArg)
                        val projection = arrayOf(
                            android.provider.MediaStore.Audio.Media._ID,
                            android.provider.MediaStore.Audio.Media.TITLE,
                            android.provider.MediaStore.Audio.Media.ARTIST,
                            android.provider.MediaStore.Audio.Media.ALBUM,
                            android.provider.MediaStore.Audio.Media.DURATION,
                            android.provider.MediaStore.Audio.Media.DATA,
                            android.provider.MediaStore.Audio.Media.ALBUM_ID,
                            android.provider.MediaStore.Audio.Media.ARTIST_ID,
                            android.provider.MediaStore.Audio.Media.DATE_ADDED,
                            android.provider.MediaStore.Audio.Media.SIZE,
                            android.provider.MediaStore.Audio.Media.MIME_TYPE,
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) android.provider.MediaStore.Audio.Media.RELATIVE_PATH else android.provider.MediaStore.Audio.Media.DATA
                        )
                        val cursor = context.contentResolver.query(
                            android.provider.MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                            projection,
                            selection,
                            args,
                            "${android.provider.MediaStore.Audio.Media.DISPLAY_NAME} ASC"
                        )
                        cursor?.use { c ->
                            while (c.moveToNext()) {
                                createSongFromCursorCompat(c)?.let { s ->
                                    if (isValidAudioFile(s.path)) result.add(s)
                                }
                            }
                        }
                    }
                } else {
                    // Fallback handled by the slow recursive scan elsewhere
                }
            } catch (_: Exception) {}
        }
        result
    }
    
    private fun stableKey(song: Song): String {
        return try {
            // Prefer MediaStore ID when available (covers content:// and MediaStore-backed scans)
            if (song.id > 0L) {
                "msid:${song.id}"
            } else if (!song.path.startsWith("content://")) {
                // Use normalized absolute path when accessible
                "path:${song.path.lowercase()}"
            } else {
                // Fallback: filename + size + duration heuristic
                val name = try { java.io.File(song.path).name.lowercase() } catch (_: Exception) { song.displayName.lowercase() }
                "meta:$name|${song.size}|${song.duration}"
            }
        } catch (_: Exception) {
            "path:${song.path}"
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
