package com.stash.opusplayer.data.database

import androidx.room.*
import kotlinx.coroutines.flow.Flow

// Row model for playlists with song counts
data class PlaylistWithCount(
    val id: Long,
    val name: String,
    val songCount: Int
)

@Dao
interface PlaylistDao {

    // Playlists
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertPlaylist(playlist: PlaylistEntity): Long

    @Query("DELETE FROM playlists WHERE id = :playlistId")
    suspend fun deletePlaylist(playlistId: Long)

    @Query(
        "SELECT p.id AS id, p.name AS name, COUNT(t.id) AS songCount " +
            "FROM playlists p LEFT JOIN playlist_tracks t ON p.id = t.playlistId " +
            "GROUP BY p.id, p.name ORDER BY p.createdAt DESC"
    )
    fun getPlaylistsWithCount(): Flow<List<PlaylistWithCount>>

    // Tracks
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertTrack(track: PlaylistTrackEntity): Long

    @Query("DELETE FROM playlist_tracks WHERE id = :trackId")
    suspend fun deleteTrackById(trackId: Long)

    @Query("DELETE FROM playlist_tracks WHERE playlistId = :playlistId AND songId = :songId")
    suspend fun deleteTrackByPlaylistAndSong(playlistId: Long, songId: Long)

    @Query("SELECT * FROM playlist_tracks WHERE playlistId = :playlistId ORDER BY addedAt ASC")
    fun getTracks(playlistId: Long): Flow<List<PlaylistTrackEntity>>
}
