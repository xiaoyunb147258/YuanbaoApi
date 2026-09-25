package dev.yuanbao2api.util

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object Logger {
    private const val MAX = 500

    data class Entry(val time: String, val text: String)

    private val buffer = ArrayDeque<Entry>()
    private val listeners = mutableListOf<(Entry) -> Unit>()
    private val fmt = SimpleDateFormat("HH:mm:ss", Locale.getDefault())

    @Synchronized
    fun log(msg: String) {
        val e = Entry(fmt.format(Date()), msg)
        buffer.addLast(e)
        if (buffer.size > MAX) buffer.removeFirst()
        listeners.toList().forEach { it(e) }
    }

    @Synchronized
    fun addListener(l: (Entry) -> Unit) { listeners.add(l) }

    @Synchronized
    fun removeListener(l: (Entry) -> Unit) { listeners.remove(l) }

    @Synchronized
    fun all(): List<Entry> = buffer.toList()

    @Synchronized
    fun clear() = buffer.clear()
}
