package com.stash.opusplayer.utils

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.concurrent.atomic.AtomicInteger

object ImageDownloadTracker {
    private val counter = AtomicInteger(0)
    private val _active = MutableStateFlow(0)
    val active: StateFlow<Int> = _active.asStateFlow()

    fun begin() {
        val v = counter.incrementAndGet()
        _active.value = v
    }

    fun end() {
        val v = counter.decrementAndGet().coerceAtLeast(0)
        counter.set(v)
        _active.value = v
    }
}
