package com.deskctrl.deskctrl

import android.content.Context
import android.media.AudioManager

/** Only the media stream changes; calls, alarms and ringer settings are untouched. */
class PhoneMediaVolume(context: Context) {
    private val audio = context.getSystemService(AudioManager::class.java)
    private val prefs = context.getSharedPreferences("vil_phone_audio_volume", Context.MODE_PRIVATE)
    private val lease = PhoneVolumeLease(
        read = { audio.getStreamVolume(AudioManager.STREAM_MUSIC) },
        write = { value -> audio.setStreamVolume(AudioManager.STREAM_MUSIC,
            value.coerceIn(0, audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)), 0) },
        loadSaved = { if (prefs.contains("original")) prefs.getInt("original", 0) else null },
        save = { value ->
            val edit = prefs.edit()
            if (value == null) edit.remove("original") else edit.putInt("original", value)
            check(edit.commit()) { "Cannot save the previous phone volume." }
        },
    )

    fun setPlayPhone(enabled: Boolean) {
        if (enabled) lease.restore() else lease.silence()
    }

    fun restore() = lease.restore()
}
