package com.stash.opusplayer.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.widget.RemoteViews
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.stash.opusplayer.R
import com.stash.opusplayer.service.MusicService
import com.stash.opusplayer.ui.MainActivity
import com.google.common.util.concurrent.MoreExecutors

class PlayerWidgetProvider : AppWidgetProvider() {

    companion object {
        const val ACTION_PLAY_PAUSE = "com.stash.opusplayer.widgets.PLAY_PAUSE"
        const val ACTION_NEXT = "com.stash.opusplayer.widgets.NEXT"
        const val ACTION_PREV = "com.stash.opusplayer.widgets.PREV"
        const val ACTION_REWIND_10 = "com.stash.opusplayer.widgets.REWIND_10"
        const val ACTION_FF_10 = "com.stash.opusplayer.widgets.FF_10"
        const val ACTION_UPDATE = "com.stash.opusplayer.widgets.UPDATE"
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_PLAY_PAUSE -> togglePlayPause(context)
            ACTION_NEXT -> sendNext(context)
            ACTION_PREV -> sendPrev(context)
            ACTION_REWIND_10 -> sendSeekDelta(context, -10_000)
            ACTION_FF_10 -> sendSeekDelta(context, 10_000)
            ACTION_UPDATE -> updateAll(context)
        }
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        updateAll(context)
    }

    private fun updateAll(context: Context) {
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val widgetComponent = ComponentName(context, PlayerWidgetProvider::class.java)
        val ids = appWidgetManager.getAppWidgetIds(widgetComponent)
        if (ids.isEmpty()) return

        val sessionToken = SessionToken(context, ComponentName(context, MusicService::class.java))
        val controllerFuture = MediaController.Builder(context, sessionToken).buildAsync()
        controllerFuture.addListener({
            val controller = runCatching { controllerFuture.get() }.getOrNull()
            if (controller == null) {
                MediaController.releaseFuture(controllerFuture)
                return@addListener
            }
            val isPlaying = controller.isPlaying
            val title = controller.mediaMetadata.title ?: "Unknown Title"
            val artist = controller.mediaMetadata.artist ?: "Unknown Artist"

            val views = RemoteViews(context.packageName, R.layout.widget_player_small)
            views.setTextViewText(R.id.widgetTitle, title)
            views.setTextViewText(R.id.widgetArtist, artist)
            views.setImageViewResource(R.id.widgetPlayPause, if (isPlaying) R.drawable.ic_pause_24 else R.drawable.ic_play_arrow_24)

            val bmp = loadArtworkBitmap(context, title.toString(), artist.toString(), controller.mediaMetadata.albumTitle?.toString() ?: "")
            if (bmp != null) {
                views.setImageViewBitmap(R.id.widgetArtwork, bmp)
            } else {
                views.setImageViewResource(R.id.widgetArtwork, R.drawable.ic_music_note)
            }

            // Wire buttons
            views.setOnClickPendingIntent(R.id.widgetContainer, launchMainPendingIntent(context))
            views.setOnClickPendingIntent(R.id.widgetPlayPause, broadcastPendingIntent(context, ACTION_PLAY_PAUSE))
            views.setOnClickPendingIntent(R.id.widgetNext, broadcastPendingIntent(context, ACTION_NEXT))
            views.setOnClickPendingIntent(R.id.widgetPrev, broadcastPendingIntent(context, ACTION_PREV))
            views.setOnClickPendingIntent(R.id.widgetRewind, broadcastPendingIntent(context, ACTION_REWIND_10))
            views.setOnClickPendingIntent(R.id.widgetFfwd, broadcastPendingIntent(context, ACTION_FF_10))

            ids.forEach { id -> appWidgetManager.updateAppWidget(id, views) }

            MediaController.releaseFuture(controllerFuture)
        }, MoreExecutors.directExecutor())
    }

    private fun togglePlayPause(context: Context) {
        val sessionToken = SessionToken(context, ComponentName(context, MusicService::class.java))
        val controllerFuture = MediaController.Builder(context, sessionToken).buildAsync()
        controllerFuture.addListener({
            val controller = runCatching { controllerFuture.get() }.getOrNull()
            if (controller == null) {
                MediaController.releaseFuture(controllerFuture)
                return@addListener
            }
            if (controller.isPlaying) controller.pause() else controller.play()
            MediaController.releaseFuture(controllerFuture)
            // Request widget UI refresh
            context.sendBroadcast(Intent(ACTION_UPDATE).setComponent(ComponentName(context, PlayerWidgetProvider::class.java)))
        }, MoreExecutors.directExecutor())
    }

    private fun sendNext(context: Context) {
        val sessionToken = SessionToken(context, ComponentName(context, MusicService::class.java))
        val controllerFuture = MediaController.Builder(context, sessionToken).buildAsync()
        controllerFuture.addListener({
            val controller = runCatching { controllerFuture.get() }.getOrNull()
            if (controller == null) {
                MediaController.releaseFuture(controllerFuture)
                return@addListener
            }
            controller.seekToNext()
            MediaController.releaseFuture(controllerFuture)
            // Request widget UI refresh
            context.sendBroadcast(Intent(ACTION_UPDATE).setComponent(ComponentName(context, PlayerWidgetProvider::class.java)))
        }, MoreExecutors.directExecutor())
    }

    private fun sendPrev(context: Context) {
        val sessionToken = SessionToken(context, ComponentName(context, MusicService::class.java))
        val controllerFuture = MediaController.Builder(context, sessionToken).buildAsync()
        controllerFuture.addListener({
            val controller = runCatching { controllerFuture.get() }.getOrNull()
            if (controller == null) {
                MediaController.releaseFuture(controllerFuture)
                return@addListener
            }
            controller.seekToPrevious()
            MediaController.releaseFuture(controllerFuture)
            context.sendBroadcast(Intent(ACTION_UPDATE).setComponent(ComponentName(context, PlayerWidgetProvider::class.java)))
        }, MoreExecutors.directExecutor())
    }

    private fun sendSeekDelta(context: Context, deltaMs: Long) {
        val sessionToken = SessionToken(context, ComponentName(context, MusicService::class.java))
        val controllerFuture = MediaController.Builder(context, sessionToken).buildAsync()
        controllerFuture.addListener({
            val controller = runCatching { controllerFuture.get() }.getOrNull()
            if (controller == null) {
                MediaController.releaseFuture(controllerFuture)
                return@addListener
            }
            val pos = controller.currentPosition
            val dur = controller.duration
            val newPos = if (deltaMs >= 0) (pos + deltaMs).coerceAtMost(if (dur > 0) dur else Long.MAX_VALUE) else (pos + deltaMs).coerceAtLeast(0)
            controller.seekTo(newPos)
            MediaController.releaseFuture(controllerFuture)
            context.sendBroadcast(Intent(ACTION_UPDATE).setComponent(ComponentName(context, PlayerWidgetProvider::class.java)))
        }, MoreExecutors.directExecutor())
    }

    private fun loadArtworkBitmap(context: Context, title: String, artist: String, album: String): Bitmap? {
        return try {
            val cache = com.stash.opusplayer.artwork.ArtworkCache(context)
            cache.loadBitmapForMetadata(title, artist, album, 256)
        } catch (_: Exception) {
            null
        }
    }

    private fun broadcastPendingIntent(context: Context, action: String): PendingIntent {
        val intent = Intent(context, PlayerWidgetProvider::class.java).apply { this.action = action }
        return PendingIntent.getBroadcast(context, action.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun launchMainPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
        return PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }
}
