package id.nekios.bluetooth_rfcomm

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
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
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID

/**
 * Bluetooth Classic (RFCOMM) client plugin for nekios-remote: a RAW
 * byte pipe to the masjid-you TV display (Route A).
 *
 * Ported from the client half of masjid-you's `bluetooth_sync` plugin
 * (same channel contract and connect behaviour: insecure RFCOMM,
 * bonded-first socket with the reflection fallback, 15 s connect
 * watchdog, runtime permission flow). Deliberate differences:
 *  - No host side (this app is never a display).
 *  - No framing and no discoverable mode: the 4-byte big-endian
 *    length framing lives in the Dart layer of nekios-remote so it is
 *    unit-testable; bytes on the wire are identical.
 */
class BluetoothRfcommPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener,
    PluginRegistry.RequestPermissionsResultListener,
    EventChannel.StreamHandler {

    companion object {
        private const val METHOD_CHANNEL = "id.nekios/bluetooth_rfcomm"
        private const val EVENT_CHANNEL = "id.nekios/bluetooth_rfcomm/events"
        private const val REQUEST_ENABLE_BT = 2001
        private const val REQUEST_PERMISSIONS = 2002

        // Wall-clock guard for the blocking connect() in ConnectThread
        // (same value/reasoning as the masjid-you plugin: SDP/RFCOMM
        // channel lookup on a stale bond can block for minutes).
        private const val CONNECT_WATCHDOG_MS = 15_000L
    }

    private lateinit var context: Context
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    private var bluetoothAdapter: BluetoothAdapter? = null

    private var pendingEnableResult: MethodChannel.Result? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    // --- Connection state (one remote <-> one TV, like the source) ---
    private var connectThread: ConnectThread? = null

    @Volatile
    private var connectedThread: ConnectedThread? = null

    @Volatile
    private var connectedSocket: BluetoothSocket? = null

    // --- Discovery ---
    private var discoveryReceiver: BroadcastReceiver? = null
    private var discovering = false

    // ------------------------------------------------------------------
    // FlutterPlugin / lifecycle
    // ------------------------------------------------------------------

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        val manager =
            context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothAdapter = manager?.adapter ?: BluetoothAdapter.getDefaultAdapter()

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        stopDiscoveryInternal()
        disconnectInternal()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        activity = binding.activity
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        onDetachedFromActivityForConfigChanges()
    }

    // ------------------------------------------------------------------
    // EventChannel
    // ------------------------------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun emit(event: Map<String, Any?>) {
        val sink = eventSink ?: return
        mainHandler.post { sink.success(event) }
    }

    private fun emitError(message: String) {
        emit(mapOf("type" to "error", "message" to message))
    }

    // ------------------------------------------------------------------
    // Activity results / permissions
    // ------------------------------------------------------------------

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == REQUEST_ENABLE_BT) {
            val enabled = resultCode == Activity.RESULT_OK && isEnabled()
            pendingEnableResult?.success(enabled)
            pendingEnableResult = null
            return true
        }
        return false
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode == REQUEST_PERMISSIONS) {
            pendingPermissionResult?.success(hasAllPermissions())
            pendingPermissionResult = null
            return true
        }
        return false
    }

    private fun requiredPermissions(): Array<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.BLUETOOTH_SCAN
            )
        } else {
            arrayOf(
                Manifest.permission.BLUETOOTH,
                Manifest.permission.BLUETOOTH_ADMIN,
                Manifest.permission.ACCESS_FINE_LOCATION
            )
        }
    }

    private fun hasAllPermissions(): Boolean {
        val act = activity ?: return false
        return requiredPermissions().all { permission ->
            ContextCompat.checkSelfPermission(act, permission) ==
                PackageManager.PERMISSION_GRANTED
        }
    }

    /**
     * Ensures the runtime Bluetooth permissions are granted before
     * running [block]. Returns true if [block] was invoked.
     * (Identical flow to the masjid-you plugin.)
     */
    private fun ensurePermissions(result: MethodChannel.Result, block: () -> Unit): Boolean {
        if (hasAllPermissions()) {
            block()
            return true
        }
        val act = activity
        if (act == null) {
            result.error("NO_ACTIVITY", "Tidak ada activity untuk meminta izin Bluetooth", null)
            return false
        }
        pendingPermissionResult?.success(false)
        pendingPermissionResult = object : MethodChannel.Result {
            override fun success(value: Any?) {
                val granted = value as? Boolean ?: false
                if (granted) {
                    block()
                    result.success(true)
                } else {
                    result.error("PERMISSION_DENIED", "Izin Bluetooth ditolak", null)
                }
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                result.error(errorCode, errorMessage, errorDetails)
            }

            override fun notImplemented() {
                result.notImplemented()
            }
        }
        ActivityCompat.requestPermissions(act, requiredPermissions(), REQUEST_PERMISSIONS)
        return false
    }

    // ------------------------------------------------------------------
    // MethodCallHandler
    // ------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(bluetoothAdapter != null)
            "isEnabled" -> result.success(isEnabled())
            "enable" -> enableBluetooth(result)
            "hasPermission" -> result.success(hasAllPermissions())
            "requestPermission" -> requestPermission(result)
            "getBondedDevices" -> {
                ensurePermissions(result) { result.success(bondedDevices()) }
            }

            "startDiscovery" -> {
                ensurePermissions(result) { result.success(startDiscoveryInternal()) }
            }

            "stopDiscovery" -> {
                stopDiscoveryInternal()
                result.success(true)
            }

            "connect" -> {
                val address = call.argument<String>("address")
                val uuidString = call.argument<String>("uuid")
                if (address == null || uuidString == null) {
                    result.error("INVALID_ARGUMENT", "address dan uuid wajib diisi", null)
                    return
                }
                ensurePermissions(result) {
                    connectInternal(address, uuidString, result)
                }
            }

            "disconnect" -> {
                disconnectInternal()
                result.success(true)
            }

            "isConnected" -> result.success(connectedSocket?.isConnected == true)
            "send" -> sendBytes(call.arguments, result)
            else -> result.notImplemented()
        }
    }

    private fun isEnabled(): Boolean {
        return try {
            bluetoothAdapter?.isEnabled == true
        } catch (e: SecurityException) {
            false
        }
    }

    private fun enableBluetooth(result: MethodChannel.Result) {
        val adapter = bluetoothAdapter
        if (adapter == null) {
            result.error("NOT_SUPPORTED", "Bluetooth tidak didukung di perangkat ini", null)
            return
        }
        if (isEnabled()) {
            result.success(true)
            return
        }
        val act = activity
        if (act == null) {
            result.error("NO_ACTIVITY", "Tidak ada activity untuk menyalakan Bluetooth", null)
            return
        }
        pendingEnableResult = result
        @Suppress("DEPRECATION")
        val intent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
        try {
            act.startActivityForResult(intent, REQUEST_ENABLE_BT)
        } catch (e: SecurityException) {
            pendingEnableResult = null
            result.error("SECURITY", "Izin Bluetooth belum diberikan", null)
        }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (hasAllPermissions()) {
            result.success(true)
            return
        }
        val act = activity
        if (act == null) {
            result.error("NO_ACTIVITY", "Tidak ada activity untuk meminta izin Bluetooth", null)
            return
        }
        pendingPermissionResult?.success(false)
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(act, requiredPermissions(), REQUEST_PERMISSIONS)
    }

    private fun bondedDevices(): List<Map<String, String>> {
        val adapter = bluetoothAdapter ?: return emptyList()
        val bonded: Set<BluetoothDevice> = try {
            adapter.bondedDevices ?: emptySet()
        } catch (e: SecurityException) {
            emptySet()
        }
        return bonded.map { device ->
            mapOf(
                "name" to (device.name ?: ""),
                "address" to device.address
            )
        }
    }

    // ------------------------------------------------------------------
    // Discovery
    // ------------------------------------------------------------------

    private fun startDiscoveryInternal(): Boolean {
        val adapter = bluetoothAdapter ?: return false
        stopDiscoveryInternal()
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
        }
        discoveryReceiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                when (intent?.action) {
                    BluetoothDevice.ACTION_FOUND -> {
                        @Suppress("DEPRECATION")
                        val device: BluetoothDevice? =
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                        if (device != null) {
                            val name = try {
                                device.name ?: ""
                            } catch (e: SecurityException) {
                                ""
                            }
                            emit(
                                mapOf(
                                    "type" to "discovered",
                                    "name" to name,
                                    "address" to device.address
                                )
                            )
                        }
                    }

                    BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                        discovering = false
                        emit(mapOf("type" to "discoveryFinished"))
                    }
                }
            }
        }
        context.registerReceiver(discoveryReceiver, filter)
        discovering = try {
            adapter.startDiscovery()
        } catch (e: SecurityException) {
            false
        }
        return discovering
    }

    private fun stopDiscoveryInternal() {
        discoveryReceiver?.let { receiver ->
            try {
                context.unregisterReceiver(receiver)
            } catch (e: IllegalArgumentException) {
                // Already unregistered.
            }
            discoveryReceiver = null
        }
        if (discovering) {
            try {
                bluetoothAdapter?.cancelDiscovery()
            } catch (e: SecurityException) {
                // Ignore.
            }
            discovering = false
        }
    }

    // ------------------------------------------------------------------
    // Connection
    // ------------------------------------------------------------------

    private fun connectInternal(address: String, uuidString: String, result: MethodChannel.Result) {
        val adapter = bluetoothAdapter
        if (adapter == null) {
            result.error("NOT_SUPPORTED", "Bluetooth tidak didukung di perangkat ini", null)
            return
        }
        if (!isEnabled()) {
            result.error("NOT_ENABLED", "Bluetooth belum menyala", null)
            return
        }
        val uuid: UUID = try {
            UUID.fromString(uuidString)
        } catch (e: IllegalArgumentException) {
            result.error("INVALID_ARGUMENT", "UUID layanan tidak valid", null)
            return
        }
        val device: BluetoothDevice = try {
            adapter.getRemoteDevice(address)
        } catch (e: IllegalArgumentException) {
            result.error("INVALID_ARGUMENT", "Alamat Bluetooth tidak valid", null)
            return
        }

        disconnectInternal()
        stopDiscoveryInternal()
        val thread = ConnectThread(device, uuid)
        connectThread = thread
        thread.start()
        result.success(true)

        // Watchdog: close the pending socket when connect() is still
        // blocked after the timeout (closing unblocks it with an
        // IOException). A stale thread (superseded by a newer
        // connection) must not kill the newer attempt.
        mainHandler.postDelayed({
            if (connectThread === thread && connectedThread == null) {
                thread.cancel()
                connectThread = null
                emitError("Koneksi Bluetooth timeout")
            }
        }, CONNECT_WATCHDOG_MS)
    }

    private fun disconnectInternal() {
        connectThread?.cancel()
        connectThread = null
        connectedThread?.cancel()
        connectedThread = null
        connectedSocket = null
    }

    private fun sendBytes(arguments: Any?, result: MethodChannel.Result) {
        val thread = connectedThread
        val bytes = arguments as? ByteArray
        if (thread == null || bytes == null) {
            result.error("NOT_CONNECTED", "Tidak ada koneksi Bluetooth aktif", null)
            return
        }
        try {
            thread.write(bytes)
            result.success(true)
        } catch (e: IOException) {
            result.error("IO_ERROR", "Gagal mengirim data: ${e.message}", null)
        }
    }

    private fun onSocketConnected(socket: BluetoothSocket, device: BluetoothDevice) {
        connectedSocket = socket
        val thread = ConnectedThread(socket)
        connectedThread = thread
        thread.start()
        val name = try {
            device.name ?: ""
        } catch (e: SecurityException) {
            ""
        }
        emit(
            mapOf(
                "type" to "connected",
                "device" to mapOf("name" to name, "address" to device.address)
            )
        )
    }

    private fun onDisconnected() {
        connectedThread = null
        connectedSocket = null
        emit(mapOf("type" to "disconnected"))
    }

    // ------------------------------------------------------------------
    // Threads
    // ------------------------------------------------------------------

    private inner class ConnectThread(
        private val device: BluetoothDevice,
        private val uuid: UUID
    ) : Thread("rfcomm-connect") {

        @Volatile
        private var socket: BluetoothSocket? = null

        @Volatile
        private var cancelled = false

        override fun run() {
            // Prefer the bonded (secure) socket — identical strategy to
            // the masjid-you plugin — then fall back to the insecure
            // socket created via reflection (some stacks return a null
            // insecure socket from the public API).
            var lastError: IOException? = null
            val secure = tryCreateSocket { device.createRfcommSocketToServiceRecord(uuid) }
            val connected: BluetoothSocket? = if (secure != null) {
                socket = secure
                try {
                    secure.connect()
                    secure
                } catch (e: IOException) {
                    lastError = e
                    closeQuietly(secure)
                    socket = null
                    null
                }
            } else {
                null
            }
            val established: BluetoothSocket? = connected ?: run {
                if (cancelled) return
                val insecure = tryCreateSocket { createInsecureSocketViaReflection(device, uuid) }
                    ?: tryCreateSocket { device.createInsecureRfcommSocketToServiceRecord(uuid) }
                if (insecure == null) {
                    if (!cancelled) {
                        emitError("Gagal membuat socket Bluetooth: ${lastError?.message ?: "tidak diketahui"}")
                    }
                    return
                }
                socket = insecure
                try {
                    insecure.connect()
                    insecure
                } catch (e: IOException) {
                    lastError = e
                    closeQuietly(insecure)
                    socket = null
                    null
                }
            }
            if (established == null) {
                if (!cancelled) {
                    emitError("Gagal terhubung ke TV: ${lastError?.message ?: "tidak diketahui"}")
                }
                return
            }
            if (cancelled) {
                closeQuietly(established)
                return
            }
            if (connectThread !== this) {
                // Superseded by a newer connection attempt.
                closeQuietly(established)
                return
            }
            connectThread = null
            onSocketConnected(established, device)
        }

        private fun tryCreateSocket(factory: () -> BluetoothSocket?): BluetoothSocket? {
            return try {
                factory()
            } catch (e: Exception) {
                null
            }
        }

        private fun createInsecureSocketViaReflection(
            device: BluetoothDevice,
            uuid: UUID
        ): BluetoothSocket? {
            val method = device.javaClass.getMethod(
                "createInsecureRfcommSocketToServiceRecord",
                UUID::class.java
            )
            return method.invoke(device, uuid) as? BluetoothSocket
        }

        fun cancel() {
            cancelled = true
            closeQuietly(socket)
        }

        private fun closeQuietly(socket: BluetoothSocket?) {
            try {
                socket?.close()
            } catch (e: IOException) {
                // Ignore.
            }
        }
    }

    private inner class ConnectedThread(private val socket: BluetoothSocket) : Thread("rfcomm-io") {
        private val input: InputStream? = try {
            socket.inputStream
        } catch (e: IOException) {
            null
        }
        private val output: OutputStream? = try {
            socket.outputStream
        } catch (e: IOException) {
            null
        }
        private val writeLock = Any()

        @Volatile
        private var running = true

        override fun run() {
            val stream = input
            if (stream == null) {
                onDisconnected()
                return
            }
            val buffer = ByteArray(16 * 1024)
            while (running) {
                val count: Int = try {
                    stream.read(buffer)
                } catch (e: IOException) {
                    break
                }
                if (count <= 0) break
                // RAW bytes: framing happens in the Dart layer.
                val chunk = buffer.copyOf(count)
                emit(mapOf("type" to "data", "data" to chunk))
            }
            if (running) {
                running = false
                onDisconnected()
            }
        }

        @Throws(IOException::class)
        fun write(bytes: ByteArray) {
            val stream = output ?: throw IOException("Output stream tidak tersedia")
            synchronized(writeLock) {
                stream.write(bytes)
                stream.flush()
            }
        }

        fun cancel() {
            running = false
            try {
                socket.close()
            } catch (e: IOException) {
                // Ignore.
            }
        }
    }
}
