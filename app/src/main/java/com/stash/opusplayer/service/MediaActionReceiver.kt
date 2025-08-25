package com.stash.opusplayer.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.ComponentName
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.MoreExecutors

class MediaActionReceiver : BroadcastReceiver() {
    
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        
        val sessionToken = SessionToken(context, ComponentName(context, MusicService::class.java))
        val controllerFuture = MediaController.Builder(context, sessionToken).buildAsync()
        
        controllerFuture.addListener({
            val controller = controllerFuture.get()
            
            when (action) {
                "PLAY" -> controller.play()
                "PAUSE" -> controller.pause()
                "STOP" -> controller.stop()
                "PREVIOUS" -> controller.seekToPrevious()
                "NEXT" -> controller.seekToNext()
            }
            
            MediaController.releaseFuture(controllerFuture)
        }, MoreExecutors.directExecutor())
    }
}
