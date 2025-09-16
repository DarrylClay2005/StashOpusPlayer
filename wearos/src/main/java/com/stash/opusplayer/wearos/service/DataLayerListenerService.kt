package com.stash.opusplayer.wearos.service

import android.util.Log
import com.google.android.gms.wearable.*
import com.stash.opusplayer.wearos.data.*
import com.stash.opusplayer.wearos.repository.WearMusicRepository
import kotlinx.coroutines.*
import org.json.JSONObject

class DataLayerListenerService : WearableListenerService() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private lateinit var musicRepository: WearMusicRepository

    companion object {
        private const val TAG = "DataLayerListener"
    }

    override fun onCreate() {
        super.onCreate()
        musicRepository = WearMusicRepository.getInstance(this)
        Log.d(TAG, "DataLayerListenerService created")
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
    }

    override fun onDataChanged(dataEventBuffer: DataEventBuffer) {
        Log.d(TAG, "Data changed events received: ${dataEventBuffer.count}")
        
        dataEventBuffer.forEach { dataEvent ->
            when (dataEvent.type) {
                DataEvent.TYPE_CHANGED -> {
                    val dataItem = dataEvent.dataItem
                    handleDataChanged(dataItem)
                }
                DataEvent.TYPE_DELETED -> {
                    Log.d(TAG, "Data deleted: ${dataEvent.dataItem.uri.path}")
                }
            }
        }
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        Log.d(TAG, "Message received: ${messageEvent.path}")
        
        when (messageEvent.path) {
            WearDataPaths.CONTROL_REQUEST -> {
                // Handle immediate control requests if needed
                Log.d(TAG, "Control request received on watch")
            }
        }
    }

    override fun onCapabilityChanged(capabilityInfo: CapabilityInfo) {
        Log.d(TAG, "Capability changed: ${capabilityInfo.name}")
        // Handle phone app capability changes
        val connectedNodes = capabilityInfo.nodes.filter { it.isNearby }
        musicRepository.updatePhoneConnected(connectedNodes.isNotEmpty())
    }

    private fun handleDataChanged(dataItem: DataItem) {
        val path = dataItem.uri.path
        Log.d(TAG, "Handling data change for path: $path")

        try {
            when (path) {
                WearDataPaths.PLAYBACK_STATE -> {
                    val dataMap = DataMapItem.fromDataItem(dataItem).dataMap
                    val playbackState = parsePlaybackState(dataMap)
                    musicRepository.updatePlaybackState(playbackState)
                }
                
                WearDataPaths.PLAYLIST -> {
                    val dataMap = DataMapItem.fromDataItem(dataItem).dataMap
                    val playlist = parsePlaylist(dataMap)
                    musicRepository.updatePlaylist(playlist)
                }
                
                WearDataPaths.CURRENT_SONG -> {
                    val dataMap = DataMapItem.fromDataItem(dataItem).dataMap
                    val song = parseSong(dataMap)
                    musicRepository.updateCurrentSong(song)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error parsing data item", e)
        }
    }

    private fun parsePlaybackState(dataMap: DataMap): WearPlaybackState {
        val currentSongMap = dataMap.getDataMap("currentSong")
        val currentSong = if (currentSongMap != null) {
            WearSong(
                id = currentSongMap.getLong("id"),
                title = currentSongMap.getString("title") ?: "",
                artist = currentSongMap.getString("artist") ?: "",
                album = currentSongMap.getString("album") ?: "",
                duration = currentSongMap.getLong("duration"),
                artworkUrl = currentSongMap.getString("artworkUrl")
            )
        } else null

        return WearPlaybackState(
            isPlaying = dataMap.getBoolean("isPlaying"),
            currentSong = currentSong,
            position = dataMap.getLong("position"),
            duration = dataMap.getLong("duration"),
            isShuffling = dataMap.getBoolean("isShuffling"),
            repeatMode = dataMap.getInt("repeatMode"),
            hasNext = dataMap.getBoolean("hasNext"),
            hasPrevious = dataMap.getBoolean("hasPrevious")
        )
    }

    private fun parsePlaylist(dataMap: DataMap): WearPlaylist {
        val songsArrayList = dataMap.getDataMapArrayList("songs")
        val songs = songsArrayList?.map { songMap ->
            WearSong(
                id = songMap.getLong("id"),
                title = songMap.getString("title") ?: "",
                artist = songMap.getString("artist") ?: "",
                album = songMap.getString("album") ?: "",
                duration = songMap.getLong("duration"),
                artworkUrl = songMap.getString("artworkUrl")
            )
        } ?: emptyList()

        return WearPlaylist(
            songs = songs,
            currentIndex = dataMap.getInt("currentIndex")
        )
    }

    private fun parseSong(dataMap: DataMap): WearSong {
        return WearSong(
            id = dataMap.getLong("id"),
            title = dataMap.getString("title") ?: "",
            artist = dataMap.getString("artist") ?: "",
            album = dataMap.getString("album") ?: "",
            duration = dataMap.getLong("duration"),
            artworkUrl = dataMap.getString("artworkUrl")
        )
    }
}
