package com.rideatlas.rideatlas

import android.app.Activity
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.documentfile.provider.DocumentFile
import com.rideatlas.rideatlas.car.CarRecordingBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/** Also used by [com.rideatlas.rideatlas.car.RideAtlasCarSession] to find
 * this Activity's Dart engine from outside the Activity lifecycle. */
const val CAR_FLUTTER_ENGINE_ID = "rideatlas_car_engine"
private const val CAR_METHOD_CHANNEL = "com.rideatlas.app/car"
private const val BATTERY_METHOD_CHANNEL = "com.rideatlas.app/battery"
private const val SATELLITE_METHOD_CHANNEL = "com.rideatlas.app/satellites"
private const val OPEN_FILE_METHOD_CHANNEL = "com.rideatlas.app/open_file"
private const val BACKUP_FOLDER_METHOD_CHANNEL = "com.rideatlas.app/backup_folder"
private const val REQ_PICK_BACKUP_TREE = 41901

class MainActivity : FlutterActivity() {

    // Created in configureFlutterEngine(), not as a field initializer:
    // applicationContext isn't available yet at construction time (Android
    // calls attachBaseContext() only after the Activity object exists).
    private var satelliteTracker: GnssSatelliteTracker? = null

    // Held until Dart asks for it (cold start from a VIEW/SEND intent) or
    // pushed via invokeMethod("onOpened") once the Dart handler is ready
    // (app already running, onNewIntent).
    private var pendingOpen: Map<String, Any>? = null
    private var openFileChannel: MethodChannel? = null
    private var dartReadyForOpens = false
    private var pendingTreePickResult: MethodChannel.Result? = null

    // Deliberately NOT overriding provideFlutterEngine() here: doing so
    // previously made FlutterActivity treat the engine as host-provided,
    // which skips its normal create-with-host/destroy-with-host lifecycle -
    // and broke background GPS tracking, since the geolocator plugin's
    // foreground-location service depends on that lifecycle running
    // normally. The engine is created and destroyed exactly the stock way;
    // this only adds a lookup for the Android Auto session to reach it
    // through, while this Activity happens to be alive.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FlutterEngineCache.getInstance().put(CAR_FLUTTER_ENGINE_ID, flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CAR_METHOD_CHANNEL)
        channel.setMethodCallHandler { call, result ->
            if (call.method == "updateState") {
                CarRecordingBridge.handleUpdate(call)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
        CarRecordingBridge.attach(channel)

        // Many OEM Android skins (MIUI, ColorOS, OneUI, ...) throttle or
        // kill even a proper foreground service's GPS updates once the
        // screen turns off, unless the app is exempted from battery
        // optimization. A foreground service alone isn't always enough on
        // these skins, so RecordScreen calls this to prompt the user
        // directly instead of silently losing the track.
        val batteryChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BATTERY_METHOD_CHANNEL,
        )
        batteryChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> result.success(isIgnoringBatteryOptimizations())
                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // A plain request/response method rather than an EventChannel
        // stream: SatelliteCountBadge polls this every couple of seconds,
        // which is plenty for a slowly-changing display value, and avoids
        // EventChannel.receiveBroadcastStream()'s behavior of reporting a
        // missing platform handler through FlutterError instead of the
        // stream itself (which made it fail Flutter's own widget tests,
        // since their harness has no native platform to answer channel
        // calls at all).
        val tracker = satelliteTracker ?: GnssSatelliteTracker(applicationContext)
        satelliteTracker = tracker
        val satelliteChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SATELLITE_METHOD_CHANNEL,
        )
        satelliteChannel.setMethodCallHandler { call, result ->
            if (call.method == "getSatelliteCount") {
                result.success(tracker.lastUsedInFixCount)
            } else {
                result.notImplemented()
            }
        }

        // Native GPS recording FGS - survives screen-off where Dart-side
        // geolocator streams freeze with the Flutter engine.
        RecordingNativeBridge.attach(
            applicationContext,
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        )

        // GPX/KML/KMZ opened via "Şununla aç" / share sheet.
        val openChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            OPEN_FILE_METHOD_CHANNEL,
        )
        openFileChannel = openChannel
        openChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "takeInitialOpen" -> {
                    // Dart is ready to receive further onOpened pushes.
                    dartReadyForOpens = true
                    val payload = pendingOpen
                    pendingOpen = null
                    result.success(payload)
                }
                else -> result.notImplemented()
            }
        }

        // Daily backup folder (SAF tree URI) - typically a Google Drive
        // folder the rider picks once; each completed local day writes one
        // GPX into it (see DailyDriveBackupController).
        val backupChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BACKUP_FOLDER_METHOD_CHANNEL,
        )
        backupChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFolder" -> pickBackupFolder(result)
                "writeFile" -> {
                    val uri = call.argument<String>("uri")
                    val fileName = call.argument<String>("fileName")
                    val bytes = call.argument<ByteArray>("bytes")
                    if (uri.isNullOrEmpty() || fileName.isNullOrEmpty() || bytes == null) {
                        result.success(false)
                    } else {
                        result.success(writeBackupFile(uri, fileName, bytes))
                    }
                }
                "folderDisplayName" -> {
                    val uri = call.argument<String>("uri")
                    result.success(if (uri.isNullOrEmpty()) null else treeDisplayName(uri))
                }
                else -> result.notImplemented()
            }
        }

        // Cold start: intent is already set when configureFlutterEngine runs.
        captureOpenIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureOpenIntent(intent)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_PICK_BACKUP_TREE) return
        val pending = pendingTreePickResult
        pendingTreePickResult = null
        if (pending == null) return
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            pending.success(null)
            return
        }
        val treeUri = data.data!!
        val flags = data.flags and
            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        try {
            contentResolver.takePersistableUriPermission(treeUri, flags)
        } catch (_: SecurityException) {
            // Some providers grant only for this session; still usable until reboot.
        }
        pending.success(
            mapOf(
                "uri" to treeUri.toString(),
                "name" to (treeDisplayName(treeUri.toString()) ?: "Drive"),
            ),
        )
    }

    private fun pickBackupFolder(result: MethodChannel.Result) {
        if (pendingTreePickResult != null) {
            result.error("busy", "Folder picker already open", null)
            return
        }
        pendingTreePickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                putExtra(DocumentsContract.EXTRA_INITIAL_URI, null as Uri?)
            }
        }
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQ_PICK_BACKUP_TREE)
        } catch (e: Exception) {
            pendingTreePickResult = null
            result.error("unavailable", e.message, null)
        }
    }

    private fun treeDisplayName(uriString: String): String? {
        return try {
            val tree = DocumentFile.fromTreeUri(this, Uri.parse(uriString))
            tree?.name
        } catch (_: Exception) {
            null
        }
    }

    private fun writeBackupFile(uriString: String, fileName: String, bytes: ByteArray): Boolean {
        return try {
            val tree = DocumentFile.fromTreeUri(this, Uri.parse(uriString)) ?: return false
            if (!tree.canWrite()) return false
            var doc = tree.findFile(fileName)
            if (doc == null || !doc.exists()) {
                doc = tree.createFile("application/gpx+xml", fileName)
                    ?: tree.createFile("application/octet-stream", fileName)
            }
            val target = doc ?: return false
            contentResolver.openOutputStream(target.uri, "wt")?.use { out ->
                out.write(bytes)
                out.flush()
            } ?: return false
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun captureOpenIntent(intent: Intent?) {
        if (intent == null) return
        val payload = readOpenPayload(intent) ?: return
        if (dartReadyForOpens) {
            openFileChannel?.invokeMethod("onOpened", payload)
        } else {
            pendingOpen = payload
        }
    }

    private fun readOpenPayload(intent: Intent): Map<String, Any>? {
        val action = intent.action ?: return null
        val uri = when (action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
                }
            }
            else -> null
        } ?: return null

        return try {
            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                ?: return null
            // Cap at 50 MB - a typical multi-day GPX is well under 5 MB;
            // anything larger is almost certainly not a track file.
            if (bytes.size > 50 * 1024 * 1024) return null
            val name = displayNameFor(uri) ?: uri.lastPathSegment ?: "track.gpx"
            mapOf(
                "name" to name,
                "bytes" to bytes,
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun displayNameFor(uri: Uri): String? {
        if (uri.scheme != "content") return uri.lastPathSegment
        var cursor: Cursor? = null
        return try {
            cursor = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            if (cursor != null && cursor.moveToFirst()) {
                val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) cursor.getString(idx) else null
            } else {
                null
            }
        } catch (_: Exception) {
            null
        } finally {
            cursor?.close()
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val powerManager = getSystemService(POWER_SERVICE) as? PowerManager ?: return true
        return powerManager.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestIgnoreBatteryOptimizations() {
        if (isIgnoringBatteryOptimizations()) return
        val intent = Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:$packageName"),
        )
        startActivity(intent)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        RecordingNativeBridge.detach()
        openFileChannel = null
        dartReadyForOpens = false
        FlutterEngineCache.getInstance().remove(CAR_FLUTTER_ENGINE_ID)
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
