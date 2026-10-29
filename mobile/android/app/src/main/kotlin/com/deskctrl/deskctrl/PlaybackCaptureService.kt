package com.deskctrl.deskctrl

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Process
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread

/** Copies permitted MEDIA/GAME playback only. No microphone, screen pixels or files. */
class PlaybackCaptureService : Service() {
    companion object {
        @Volatile var events: EventChannel.EventSink? = null
        @Volatile var running = false
        var instance: PlaybackCaptureService? = null
        var ready: ((String?) -> Unit)? = null
    }
    private val main = Handler(Looper.getMainLooper())
    private var projection: MediaProjection? = null
    private var recorder: AudioRecord? = null
    private var worker: Thread? = null
    private val queued = AtomicInteger()
    @Volatile private var stopped = false
    private val revoked = object : MediaProjection.Callback() {
        override fun onStop() {
            if (!stopped) fail("Android stopped phone audio sharing. Tap Start to approve it again.")
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "stop") { end(); return START_NOT_STICKY }
        if (running) { ready?.invoke(null); ready = null; return START_NOT_STICKY }
        instance = this
        try {
            check(Build.VERSION.SDK_INT >= 29) { "Android 10 or newer is required." }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(NotificationChannel("vil_phone_audio", "Phone audio sharing", NotificationManager.IMPORTANCE_LOW))
            val stop = PendingIntent.getService(this, 0, Intent(this, PlaybackCaptureService::class.java).setAction("stop"), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            val open = PendingIntent.getActivity(this, 1, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            val notification = Notification.Builder(this, "vil_phone_audio")
                .setSmallIcon(android.R.drawable.ic_media_play).setContentTitle("ViL · sharing phone audio")
                .setContentText("Media audio is sent to your selected computer. Tap Stop to end.")
                .setOngoing(true).setContentIntent(open)
                .addAction(Notification.Action.Builder(null, "Stop", stop).build()).build()
            startForeground(4722, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
            @Suppress("DEPRECATION")
            val data = intent?.getParcelableExtra<Intent>("resultData") ?: error("Capture consent is missing.")
            val p = getSystemService(MediaProjectionManager::class.java)
                .getMediaProjection(intent.getIntExtra("resultCode", 0), data) ?: error("Android did not grant phone audio capture.")
            projection = p
            p.registerCallback(revoked, main)
            val config = AudioPlaybackCaptureConfiguration.Builder(p)
                .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                .addMatchingUsage(AudioAttributes.USAGE_GAME)
                .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
                .excludeUid(Process.myUid()).build()
            val format = AudioFormat.Builder().setSampleRate(48000)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT).setChannelMask(AudioFormat.CHANNEL_IN_STEREO).build()
            val min = AudioRecord.getMinBufferSize(48000, AudioFormat.CHANNEL_IN_STEREO, AudioFormat.ENCODING_PCM_16BIT)
            check(min > 0) { "This phone does not support 48 kHz stereo capture." }
            val audio = AudioRecord.Builder().setAudioFormat(format)
                .setAudioPlaybackCaptureConfig(config).setBufferSizeInBytes(maxOf(min, 3840 * 4)).build()
            recorder = audio
            check(audio.state == AudioRecord.STATE_INITIALIZED) { "Phone audio capture could not initialize." }
            audio.startRecording()
            check(audio.recordingState == AudioRecord.RECORDSTATE_RECORDING) { "Phone audio capture could not start." }
            running = true
            ready?.invoke(null); ready = null
            worker = thread(name = "ViL phone playback capture") {
                Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
                try {
                    var frame = ByteArray(3840)
                    var offset = 0
                    while (!stopped) {
                        val read = audio.read(frame, offset, frame.size - offset, AudioRecord.READ_BLOCKING)
                        if (stopped) break
                        check(read > 0) { "Phone audio capture read failed ($read)." }
                        offset += read
                        if (offset == frame.size) {
                            // Never build a latency-growing main-thread backlog.
                            if (events != null && queued.get() < 2) {
                                val bytes = frame
                                queued.incrementAndGet()
                                main.post {
                                    try { if (!stopped) events?.success(bytes) } finally { queued.decrementAndGet() }
                                }
                            }
                            frame = ByteArray(3840); offset = 0
                        }
                    }
                } catch (e: Exception) {
                    main.post { if (!stopped) fail(e.message ?: "Phone capture failed.") }
                }
            }
        } catch (e: Exception) { fail(e.message ?: "Cannot share phone audio.") }
        return START_NOT_STICKY
    }

    private fun fail(message: String) {
        ready?.invoke(message); ready = null
        events?.error("playback_capture", message, null)
        stopSelf()
    }

    fun end() {
        shutdown()
        stopSelf()
    }

    private fun shutdown() {
        if (stopped) return
        stopped = true
        running = false
        try { recorder?.stop() } catch (_: Exception) {}
        worker?.join(500)
        recorder?.release(); recorder = null
        projection?.unregisterCallback(revoked)
        projection?.stop(); projection = null
        // Notification Stop and Android revocation must update Flutter too.
        events?.error("capture_stopped", "Phone audio sharing stopped.", null)
        stopForeground(STOP_FOREGROUND_REMOVE)
        instance = null
    }

    override fun onDestroy() {
        shutdown()
        super.onDestroy()
    }
}
