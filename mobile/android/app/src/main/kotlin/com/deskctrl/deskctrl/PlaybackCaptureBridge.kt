package com.deskctrl.deskctrl

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** Consent belongs to the visible activity; audio-only capture belongs to the service. */
class PlaybackCaptureBridge(private val activity: Activity, messenger: BinaryMessenger) {
    companion object { const val PERMISSION = 4720; const val PROJECTION = 4721 }
    private var pending: MethodChannel.Result? = null
    private var playPhone = false

    init {
        // A killed process may not receive Service.onDestroy. Recover its saved volume.
        if (!PlaybackCaptureService.running) {
            try { PhoneMediaVolume(activity).restore() } catch (_: Exception) {}
        }
        EventChannel(messenger, "deskctrl/playback_capture/audio").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                PlaybackCaptureService.events = events
            }
            override fun onCancel(arguments: Any?) { PlaybackCaptureService.events = null }
        })
        MethodChannel(messenger, "deskctrl/playback_capture").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> {
                        playPhone = call.argument<Boolean>("playPhone") ?: false
                        when {
                            Build.VERSION.SDK_INT < 29 -> result.error("unsupported", "Phone playback capture requires Android 10 or newer.", null)
                            PlaybackCaptureService.running -> {
                                PlaybackCaptureService.instance?.setPlayPhone(playPhone)
                                result.success(null)
                            }
                            pending != null -> result.error("busy", "Capture permission is already open.", null)
                            call.argument<Boolean>("allowConsent") == false -> result.error("capture_consent_required", "Tap Start to approve phone capture again.", null)
                            else -> {
                                pending = result
                                if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                                    activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSION)
                                } else requestProjection()
                            }
                        }
                    }
                    "playPhone" -> {
                        PlaybackCaptureService.instance?.setPlayPhone(call.argument<Boolean>("enabled") ?: false)
                        result.success(null)
                    }
                    "stop" -> {
                        pending?.error("cancelled", "Phone audio capture was cancelled.", null)
                        pending = null
                        PlaybackCaptureService.ready = null
                        PlaybackCaptureService.instance?.end()
                        activity.stopService(Intent(activity, PlaybackCaptureService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("phone_volume", e.message, null) }
        }
    }

    private fun requestProjection() {
        if (pending == null) return
        try {
            val manager = activity.getSystemService(MediaProjectionManager::class.java)
            activity.startActivityForResult(manager.createScreenCaptureIntent(), PROJECTION)
        } catch (e: Exception) { finish(e.message ?: "Cannot request audio capture.") }
    }

    fun permissionResult(grants: IntArray) {
        if (grants.firstOrNull() == PackageManager.PERMISSION_GRANTED) requestProjection()
        else finish("Audio capture permission was denied. No microphone audio is captured.")
    }

    fun activityResult(code: Int, data: Intent?) {
        if (pending == null) return
        if (code != Activity.RESULT_OK || data == null) {
            finish("Phone audio sharing was not approved.")
            return
        }
        PlaybackCaptureService.ready = { error -> finish(error) }
        try {
            activity.startForegroundService(Intent(activity, PlaybackCaptureService::class.java)
                .putExtra("resultCode", code).putExtra("resultData", data).putExtra("playPhone", playPhone))
        } catch (e: Exception) { finish(e.message ?: "Cannot start phone audio sharing.") }
    }

    private fun finish(error: String?) {
        val result = pending
        pending = null
        PlaybackCaptureService.ready = null
        if (error == null) result?.success(null) else result?.error("playback_capture", error, null)
    }

    fun destroy() {
        pending?.error("cancelled", "The capture activity was closed.", null)
        pending = null
        PlaybackCaptureService.ready = null
        PlaybackCaptureService.events = null
        PlaybackCaptureService.instance?.end()
        activity.stopService(Intent(activity, PlaybackCaptureService::class.java))
    }
}
