package com.stash.opusplayer.music.domain.repository

import com.stash.opusplayer.music.domain.models.*
import kotlinx.coroutines.flow.Flow

interface MusicRepository {
    fun observeAllTracks(): Flow<List<Track>>
    suspend fun queryTracks(query: MusicQuery): MusicQueryResult<Track>
    suspend fun getTrackById(id: TrackId): Track?
    suspend fun getTracksByIds(ids: List<TrackId>): List<Track>
    fun searchTracks(searchTerm: String): Flow<List<Track>>
    suspend fun saveTrack(track: Track)
    suspend fun saveTracks(tracks: List<Track>)
    suspend fun deleteTrack(trackId: TrackId)
    suspend fun incrementPlayCount(trackId: TrackId)
    suspend fun setFavorite(trackId: TrackId, isFavorite: Boolean)
    suspend fun setRating(trackId: TrackId, rating: Float)
    fun observeFavoriteTracks(): Flow<List<Track>>
    fun observeRecentlyPlayed(limit: Int = 50): Flow<List<Track>>
    fun observeMostPlayed(limit: Int = 50): Flow<List<Track>>
    fun observeAllAlbums(): Flow<List<Album>>
    suspend fun getAlbumById(id: AlbumId): Album?
    suspend fun getAlbumsByArtist(artistId: ArtistId): List<Album>
    suspend fun saveAlbum(album: Album)
    fun observeAllArtists(): Flow<List<Artist>>
    suspend fun getArtistById(id: ArtistId): Artist?
    suspend fun saveArtist(artist: Artist)
    fun observeAllPlaylists(): Flow<List<Playlist>>
    suspend fun getPlaylistById(id: PlaylistId): Playlist?
    suspend fun savePlaylist(playlist: Playlist)
    suspend fun deletePlaylist(playlistId: PlaylistId)
    suspend fun addTracksToPlaylist(playlistId: PlaylistId, trackIds: List<TrackId>)
    suspend fun removeTrackFromPlaylist(playlistId: PlaylistId, trackId: TrackId)
    fun observePlaylistTracks(playlistId: PlaylistId): Flow<List<Track>>
    suspend fun getTotalTrackCount(): Int
    suspend fun getTotalAlbumCount(): Int
    suspend fun getTotalArtistCount(): Int
}
