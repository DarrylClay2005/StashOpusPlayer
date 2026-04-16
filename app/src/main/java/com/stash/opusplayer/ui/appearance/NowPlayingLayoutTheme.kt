package com.stash.opusplayer.ui.appearance

enum class NowPlayingLayoutTheme(val storageValue: String, val displayName: String) {
    AURORA("aurora", "Aurora"),
    VINYL("vinyl", "Vinyl Stack"),
    MINIMAL("minimal", "Minimal Deck");

    companion object {
        fun fromStorage(value: String?): NowPlayingLayoutTheme {
            return entries.firstOrNull { it.storageValue.equals(value, ignoreCase = true) } ?: AURORA
        }
    }
}
