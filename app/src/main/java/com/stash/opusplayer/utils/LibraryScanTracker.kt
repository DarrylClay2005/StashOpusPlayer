package com.stash.opusplayer.utils

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

object LibraryScanTracker {
    private val _status = MutableStateFlow("Initializing…")
    val status: StateFlow<String> = _status

    fun update(message: String) {
        _status.value = message
    }
}
