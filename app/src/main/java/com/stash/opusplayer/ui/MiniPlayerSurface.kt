package com.stash.opusplayer.ui

import android.view.View
import androidx.lifecycle.LifecycleOwner
import com.stash.opusplayer.player.MusicPlayerManager
import com.stash.opusplayer.ui.appearance.AppearancePreferences

interface MiniPlayerSurface {
    fun initialize(lifecycleOwner: LifecycleOwner, musicPlayerManager: MusicPlayerManager)
    fun resync()
    fun release()
    fun applyAppearancePreferences(prefs: AppearancePreferences)
    fun asView(): View
}
