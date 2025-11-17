package com.stash.opusplayer.player.domain.models

/**
 * STUB - Current Track model
 */
data class CurrentTrack(
    val trackId: String = "",
    val title: String = "",
    val artist: String = "",
    val album: String = "",
    val duration: Long = 0L,
    val path: String = "",
    val uri: String = "" // URI for media playback
)

data class LoadTrackOptions(
    val performAnalysis: Boolean = false,
    val prepareImmediately: Boolean = true
)

data class PlaybackOptions(
    val optimizeForPlayback: Boolean = true
)

data class AudioAnalysisResult(
    val quality: Float = 0f,
    val genre: String = "",
    val tempo: Float = 0f
)

data class AudioPerformanceMetrics(
    val bufferHealth: Float = 1.0f,
    val cpuUsage: Float = 0f,
    val dropouts: Int = 0
)

data class AudioEffectState(
    val enabled: Boolean = false,
    val intensity: Float = 0.5f
)

enum class AudioEngineState {
    IDLE, INITIALIZING, READY, PLAYING, PAUSED, BUFFERING, ERROR
}

sealed class AudioEngineEvent {
    object InitializationStarted : AudioEngineEvent()
    object InitializationCompleted : AudioEngineEvent()
    data class TrackLoadStarted(val trackId: String) : AudioEngineEvent()
    data class TrackLoaded(val trackId: String) : AudioEngineEvent()
    object PlaybackStarted : AudioEngineEvent()
    object PlaybackPaused : AudioEngineEvent()
    object PlaybackStopped : AudioEngineEvent()
    data class Error(val message: String) : AudioEngineEvent()
}

data class AudioEngineResult(
    val success: Boolean,
    val message: String = "",
    val error: String? = null
) {
    companion object {
        fun success(message: String = "") = AudioEngineResult(true, message)
        fun failure(error: String) = AudioEngineResult(false, error = error)
    }
}

data class AudioEngineConfiguration(
    val intelligenceEnabled: Boolean = false,
    val realTimeAnalysisEnabled: Boolean = false,
    val crossfadeEnabled: Boolean = false,
    val gaplessEnabled: Boolean = false
)
