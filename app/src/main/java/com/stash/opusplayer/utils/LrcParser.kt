package com.stash.opusplayer.utils

data class LrcLine(val timeMs: Long, val text: String)

object LrcParser {
    private val timeRegex = Regex("\\[(\\d{1,2}):(\\d{1,2})(?:\\.(\\d{1,2}))?]")

    fun parse(content: String): List<LrcLine> {
        val lines = mutableListOf<LrcLine>()
        content.lineSequence().forEach { raw ->
            val matches = timeRegex.findAll(raw).toList()
            val text = raw.replace(timeRegex, "").trim()
            matches.forEach { m ->
                val min = m.groupValues[1].toLongOrNull() ?: 0L
                val sec = m.groupValues[2].toLongOrNull() ?: 0L
                val hund = m.groupValues.getOrNull(3)?.toLongOrNull() ?: 0L
                val ms = min * 60_000 + sec * 1_000 + hund * 10
                lines.add(LrcLine(ms, text))
            }
        }
        return lines.sortedBy { it.timeMs }
    }
}
