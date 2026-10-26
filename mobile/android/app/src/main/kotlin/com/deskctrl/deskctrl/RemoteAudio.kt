package com.deskctrl.deskctrl

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.os.Process
import java.util.concurrent.ArrayBlockingQueue
import kotlin.concurrent.thread

/** Bounded low-latency PCM player. Audio is never written to storage. */
class RemoteAudio(private val context: Context) {
    private var track: AudioTrack? = null
    private var worker: Thread? = null
    private var queue = ArrayBlockingQueue<ByteArray>(6)
    @Volatile private var running = false
    private var focus: AudioFocusRequest? = null

    @Synchronized fun start(rate: Int, channels: Int, latency: String) {
        stop()
        val mask = if (channels == 1) AudioFormat.CHANNEL_OUT_MONO else AudioFormat.CHANNEL_OUT_STEREO
        val format = AudioFormat.Builder().setSampleRate(rate).setChannelMask(mask).setEncoding(AudioFormat.ENCODING_PCM_16BIT).build()
        val frameBytes = rate * channels * 2 / 50 // 20 ms PCM
        val min = AudioTrack.getMinBufferSize(rate, mask, AudioFormat.ENCODING_PCM_16BIT)
        require(min > 0) { "Unsupported remote audio format" }
        val targetBytes = frameBytes * if (latency == "low") 2 else 3
        val bufferBytes = maxOf(min, targetBytes)
        val builder = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
            .setAudioFormat(format).setTransferMode(AudioTrack.MODE_STREAM).setBufferSizeInBytes(bufferBytes)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder.setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
        }
        val audio = builder.build()
        requestFocus()
        val frames = ArrayBlockingQueue<ByteArray>(if (latency == "low") 4 else 6)
        queue = frames
        track = audio
        running = true
        worker = thread(name = "ViL remote audio") {
            Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
            try {
                // Fill the native buffer before starting the clock. Starting empty
                // immediately underruns and makes network jitter audible.
                val pump = PcmPump(targetBytes)
                while (running && track === audio) {
                    val bytes = frames.take()
                    if (!pump.write(bytes, { running && track === audio },
                            { data, offset, count -> audio.write(data, offset, count, AudioTrack.WRITE_BLOCKING) },
                            { audio.play() })) break
                }
            } catch (_: InterruptedException) {
                // Normal stop.
            } catch (_: IllegalStateException) {
                // A concurrent stop released this generation's track.
            }
        }
    }

    fun write(bytes: ByteArray) {
        if (!running || queue.offer(bytes)) return
        queue.poll() // latency matters more than an old frame
        queue.offer(bytes)
    }

    fun gain(volume: Float, muted: Boolean) {
        track?.setVolume(if (muted) 0f else volume.coerceIn(0f, 1f))
    }

    @Synchronized fun stop() {
        running = false
        worker?.interrupt()
        worker = null
        queue.clear()
        track?.let { runCatching { it.pause(); it.flush(); it.stop(); it.release() } }
        track = null
        abandonFocus()
    }

    private fun requestFocus() {
        val manager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                .setOnAudioFocusChangeListener { change -> if (change == AudioManager.AUDIOFOCUS_LOSS) stop() }
                .build()
            manager.requestAudioFocus(focus!!)
        } else {
            @Suppress("DEPRECATION") manager.requestAudioFocus(null, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
        }
    }

    private fun abandonFocus() {
        val manager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) focus?.let { manager.abandonAudioFocusRequest(it) }
        else @Suppress("DEPRECATION") manager.abandonAudioFocus(null)
        focus = null
    }
}
