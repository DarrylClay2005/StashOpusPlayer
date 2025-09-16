package com.stash.opusplayer.wearos.complications

import android.support.wearable.complications.ComplicationData
import android.support.wearable.complications.ComplicationManager
import android.support.wearable.complications.ComplicationProviderService
import android.support.wearable.complications.ComplicationText
import com.stash.opusplayer.wearos.R
import com.stash.opusplayer.wearos.repository.WearMusicRepository

class MusicComplicationService : ComplicationProviderService() {

    private lateinit var repository: WearMusicRepository

    override fun onCreate() {
        super.onCreate()
        repository = WearMusicRepository.getInstance(this)
    }

    override fun onComplicationUpdate(
        complicationId: Int,
        dataType: Int,
        complicationManager: ComplicationManager
    ) {
        val currentSong = repository.currentSong.value
        val playbackState = repository.playbackState.value

        val complicationData = when (dataType) {
            ComplicationData.TYPE_SHORT_TEXT -> {
                if (currentSong != null) {
                    ComplicationData.Builder(ComplicationData.TYPE_SHORT_TEXT)
                        .setShortText(ComplicationText.plainText(currentSong.title))
                        .build()
                } else {
                    ComplicationData.Builder(ComplicationData.TYPE_SHORT_TEXT)
                        .setShortText(ComplicationText.plainText(getString(R.string.no_music_playing)))
                        .build()
                }
            }
            
            ComplicationData.TYPE_LONG_TEXT -> {
                if (currentSong != null && playbackState != null) {
                    val status = if (playbackState.isPlaying) "♪" else "⏸"
                    val text = "$status ${currentSong.title} - ${currentSong.artist}"
                    ComplicationData.Builder(ComplicationData.TYPE_LONG_TEXT)
                        .setLongText(ComplicationText.plainText(text))
                        .build()
                } else {
                    ComplicationData.Builder(ComplicationData.TYPE_LONG_TEXT)
                        .setLongText(ComplicationText.plainText(getString(R.string.no_music_playing)))
                        .build()
                }
            }
            
            ComplicationData.TYPE_SMALL_IMAGE -> {
                ComplicationData.Builder(ComplicationData.TYPE_SMALL_IMAGE)
                    .setSmallImage(
                        android.graphics.drawable.Icon.createWithResource(
                            this, 
                            R.drawable.ic_music_note
                        )
                    )
                    .build()
            }
            
            else -> null
        }

        if (complicationData != null) {
            complicationManager.updateComplicationData(complicationId, complicationData)
        } else {
            // Send null data to clear the complication if we can't build something for the requested type.
            complicationManager.updateComplicationData(complicationId, null)
        }
    }
}
