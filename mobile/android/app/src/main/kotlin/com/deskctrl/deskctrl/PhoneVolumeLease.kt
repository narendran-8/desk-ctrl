package com.deskctrl.deskctrl

/** Save before silencing, restore once, and recover after a killed capture process.
 * Call only from the Android main thread. Independent of the captured PCM gain.
 */
class PhoneVolumeLease(
    private val read: () -> Int,
    private val write: (Int) -> Unit,
    private val loadSaved: () -> Int?,
    private val save: (Int?) -> Unit,
) {
    private var original: Int? = null

    fun silence() {
        if (original != null) return
        val before = read()
        save(before) // durable before changing the system volume
        original = before
        try {
            write(0)
            check(read() == 0) { "Android could not silence the phone media output." }
        } catch (e: Exception) {
            restore()
            throw e
        }
    }

    fun restore() {
        val before = original ?: loadSaved() ?: return
        // Honor an explicit volume change made outside ViL while sharing.
        if (read() == 0) write(before)
        save(null)
        original = null
    }
}
