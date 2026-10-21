package com.deskctrl.deskctrl

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder

/**
 * The microphone for voice control: 16 kHz, mono, 16-bit little-endian samples (what Whistle
 * takes), delivered in pieces of 20 ms on a background thread through [onData].
 */
class Mic(private val onData: (ByteArray) -> Unit) {
    @Volatile private var recorder: AudioRecord? = null
    private var thread: Thread? = null

    @SuppressLint("MissingPermission") // the caller checked RECORD_AUDIO
    fun start(): Boolean {
        if (recorder != null) return true
        val piece = RATE / 50 * 2 // 20 ms of 16-bit samples
        val min = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        if (min <= 0) return false
        val r = try {
            AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION, RATE, AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT, maxOf(min, piece * 8),
            )
        } catch (e: Exception) {
            return false
        }
        if (r.state != AudioRecord.STATE_INITIALIZED) {
            r.release()
            return false
        }
        r.startRecording()
        recorder = r
        thread = Thread {
            val buf = ByteArray(piece)
            while (recorder === r) {
                var got = 0
                while (got < piece && recorder === r) {
                    val n = r.read(buf, got, piece - got)
                    if (n <= 0) break
                    got += n
                }
                if (got == piece && recorder === r) onData(buf.copyOf())
                else if (got == 0) break
            }
        }.also { it.isDaemon = true; it.start() }
        return true
    }

    fun stop() {
        val r = recorder ?: return
        recorder = null
        try { r.stop() } catch (_: Exception) {}
        r.release()
        thread = null
    }

    companion object {
        const val RATE = 16000
    }
}
