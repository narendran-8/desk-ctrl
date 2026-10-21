package com.deskctrl.deskctrl

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * Bluetooth Classic (RFCOMM) bridge for the Dart side. One socket per computer, keyed by
 * its Bluetooth address, so several computers can stay connected at once.
 * Bytes are passed through untouched; framing lives in Dart (lib/links.dart).
 */
@SuppressLint("MissingPermission") // checked through hasPermission() before every call
class MainActivity : FlutterActivity() {
    companion object {
        // Must match SERVICE_UUID in agent/src/bluetooth.rs
        private val SERVICE_UUID: UUID = UUID.fromString("c0de5c71-7e1a-4d1c-8d5e-d35c7c71a001")
        private const val REQ_BLUETOOTH = 4711
        private const val REQ_MIC = 4712
    }

    private val main = Handler(Looper.getMainLooper())
    private val writer = Executors.newSingleThreadExecutor()
    private var sink: EventChannel.EventSink? = null
    private var pendingPermission: MethodChannel.Result? = null
    private var pendingMic: MethodChannel.Result? = null
    private var micSink: EventChannel.EventSink? = null
    private val mic = Mic { bytes -> main.post { micSink?.success(bytes) } }

    // deskctrl://pair/... links (sent by the agent over the USB cable)
    private var linkSink: EventChannel.EventSink? = null
    private var initialLink: String? = null

    private class Conn {
        @Volatile var socket: BluetoothSocket? = null
        @Volatile var out: OutputStream? = null
    }

    /**
     * Live connections by address. A thread only acts while its Conn is still the
     * registered one, so threads of a replaced or closed connection go quiet.
     */
    private val conns = ConcurrentHashMap<String, Conn>()

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.data?.toString()?.let { link ->
            val sink = linkSink
            if (sink != null) sink.success(link) else initialLink = link
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        initialLink = intent?.data?.toString()
        MethodChannel(messenger, "deskctrl/link").setMethodCallHandler { call, result ->
            if (call.method == "initialLink") {
                result.success(initialLink)
                initialLink = null
            } else {
                result.notImplemented()
            }
        }
        EventChannel(messenger, "deskctrl/link/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { linkSink = events }
            override fun onCancel(arguments: Any?) { linkSink = null }
        })

        // The USB cable: true while the phone is connected to a computer's data port.
        EventChannel(messenger, "deskctrl/usb/state").setStreamHandler(object : EventChannel.StreamHandler {
            private var receiver: BroadcastReceiver? = null
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                val r = object : BroadcastReceiver() {
                    override fun onReceive(context: Context?, intent: Intent?) {
                        events?.success(intent?.getBooleanExtra("connected", false) ?: false)
                    }
                }
                receiver = r
                val filter = IntentFilter("android.hardware.usb.action.USB_STATE")
                if (Build.VERSION.SDK_INT >= 33) registerReceiver(r, filter, Context.RECEIVER_EXPORTED)
                else registerReceiver(r, filter)
            }
            override fun onCancel(arguments: Any?) {
                receiver?.let { try { unregisterReceiver(it) } catch (_: Exception) {} }
                receiver = null
            }
        })

        EventChannel(messenger, "deskctrl/bt/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
            override fun onCancel(arguments: Any?) { sink = null }
        })

        MethodChannel(messenger, "deskctrl/window").setMethodCallHandler { call, result ->
            if (call.method == "setCutout") {
                // Draw into the notch / camera cut-out area (or stay out of it).
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    val attrs = window.attributes
                    attrs.layoutInDisplayCutoutMode = if (call.arguments as? Boolean == true)
                        WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                    else
                        WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_DEFAULT
                    window.attributes = attrs
                }
                result.success(null)
            } else if (call.method == "setBrightness") {
                // 0 = follow the system brightness, otherwise this window's own level.
                val level = (call.arguments as? Number)?.toFloat() ?: 0f
                val attrs = window.attributes
                attrs.screenBrightness = if (level <= 0f) WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                    else level.coerceIn(0.01f, 1f)
                window.attributes = attrs
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        // The microphone, for voice control.
        EventChannel(messenger, "deskctrl/mic/audio").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { micSink = events }
            override fun onCancel(arguments: Any?) { micSink = null }
        })
        MethodChannel(messenger, "deskctrl/mic").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> startMic(result)
                "stop" -> {
                    mic.stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "deskctrl/bt").setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(adapter() != null)
                "ensurePermission" -> ensurePermission(result)
                "bondedDevices" -> bondedDevices(result)
                "connect" -> connect(call.argument<String>("address") ?: "", result)
                "write" -> {
                    write(call.argument<String>("address") ?: "", call.argument<ByteArray>("bytes") ?: ByteArray(0))
                    result.success(null)
                }
                "disconnect" -> {
                    closeConn(call.argument<String>("address") ?: "")
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        mic.stop()
        conns.keys.toList().forEach { closeConn(it) }
        super.onDestroy()
    }

    // ---- permission --------------------------------------------------------

    private fun adapter(): BluetoothAdapter? =
        (getSystemService(BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    private fun hasPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    private fun ensurePermission(result: MethodChannel.Result) {
        if (hasPermission()) {
            result.success(true)
        } else if (pendingPermission != null) {
            result.error("busy", "Permission request already in progress", null)
        } else {
            pendingPermission = result
            requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), REQ_BLUETOOTH)
        }
    }

    private fun startMic(result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            result.success(mic.start())
        } else if (pendingMic != null) {
            result.error("busy", "Permission request already in progress", null)
        } else {
            pendingMic = result
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQ_MIC)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (requestCode == REQ_MIC) {
            // The person asked for the microphone by pressing the button: start it once allowed.
            val ok = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingMic?.success(ok && mic.start())
            pendingMic = null
        }
        if (requestCode == REQ_BLUETOOTH) {
            pendingPermission?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            pendingPermission = null
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    // ---- devices -----------------------------------------------------------

    private fun bondedDevices(result: MethodChannel.Result) {
        val ad = adapter()
        when {
            ad == null -> result.error("unavailable", "This phone has no Bluetooth", null)
            !hasPermission() -> result.error("permission", "Bluetooth permission not granted", null)
            else -> result.success(ad.bondedDevices.map { mapOf("name" to (it.name ?: it.address), "address" to it.address) })
        }
    }

    // ---- connection --------------------------------------------------------

    private fun connect(address: String, result: MethodChannel.Result) {
        closeConn(address)
        val conn = Conn()
        conns[address] = conn
        Thread {
            try {
                val ad = adapter() ?: throw IllegalStateException("This phone has no Bluetooth")
                if (!ad.isEnabled) throw IllegalStateException("Bluetooth is turned off")
                if (!hasPermission()) throw IllegalStateException("Bluetooth permission not granted")
                val s = ad.getRemoteDevice(address).createRfcommSocketToServiceRecord(SERVICE_UUID)
                conn.socket = s // lets closeConn() abort a connect that is still blocking
                s.connect()
                if (conns[address] !== conn) {
                    s.close()
                    throw IllegalStateException("Cancelled")
                }
                conn.out = s.outputStream
                main.post { result.success(null) }
                readLoop(address, conn, s)
            } catch (e: Exception) {
                if (conns[address] === conn) conns.remove(address)
                conn.socket?.let { runCatching { it.close() } }
                main.post { result.error("connect", e.message ?: e.javaClass.simpleName, null) }
            }
        }.start()
    }

    /** Forwards what the desktop sends (the ACK frame) and reports when the link ends. */
    private fun readLoop(address: String, conn: Conn, s: BluetoothSocket) {
        val buf = ByteArray(256)
        try {
            val input = s.inputStream
            while (true) {
                val n = input.read(buf)
                if (n < 0 || conns[address] !== conn) break
                emit(mapOf("t" to "data", "id" to address, "b" to buf.copyOf(n)))
            }
        } catch (_: Exception) {
        }
        if (conns[address] === conn) {
            closeConn(address)
            emit(mapOf("t" to "closed", "id" to address))
        }
    }

    private fun write(address: String, bytes: ByteArray) {
        val conn = conns[address] ?: return
        writer.execute {
            try {
                conn.out?.write(bytes)
            } catch (_: Exception) {
                main.post {
                    if (conns[address] === conn) {
                        closeConn(address)
                        emit(mapOf("t" to "closed", "id" to address))
                    }
                }
            }
        }
    }

    private fun closeConn(address: String) {
        conns.remove(address)?.socket?.let { runCatching { it.close() } }
    }

    private fun emit(event: Map<String, Any>) {
        main.post { sink?.success(event) }
    }
}
