package com.deskctrl.deskctrl

/** Writes every byte, including short writes, and starts only after prebuffering. */
class PcmPump(private val prebufferBytes: Int) {
    private var primed = 0
    private var playing = false

    fun write(bytes: ByteArray, alive: () -> Boolean, output: (ByteArray, Int, Int) -> Int, play: () -> Unit): Boolean {
        var offset = 0
        while (offset < bytes.size && alive()) {
            val count = if (playing) bytes.size - offset else minOf(bytes.size - offset, prebufferBytes - primed)
            val written = output(bytes, offset, count)
            if (written <= 0 || written > count) return false
            offset += written
            if (!playing) {
                primed += written
                if (primed >= prebufferBytes) {
                    play()
                    playing = true
                }
            }
        }
        return offset == bytes.size
    }
}
