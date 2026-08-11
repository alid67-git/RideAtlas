package com.rideatlas.rideatlas

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import org.json.JSONObject
import java.io.File
import java.util.Collections

/**
 * Owns GPS collection for an in-progress ride on the native side so points
 * keep arriving while the screen is off / Flutter isolate is frozen.
 * Geolocator's Dart stream alone is not enough: OEMs suspend the Flutter
 * engine in Doze even when its own FGS is running, and then no points reach
 * Dart. This service writes every fix to an in-memory list (+ append-only
 * file) and optionally pushes live updates to [RecordingNativeBridge].
 */
class RecordingLocationService : Service() {
    companion object {
        private const val TAG = "RideAtlasRecording"
        private const val CHANNEL_ID = "rideatlas_recording"
        private const val NOTIFICATION_ID = 42001
        private const val POINTS_FILE = "active_recording_points.jsonl"

        const val ACTION_START = "com.rideatlas.rideatlas.recording.START"
        const val ACTION_STOP = "com.rideatlas.rideatlas.recording.STOP"
        const val ACTION_SET_PAUSED = "com.rideatlas.rideatlas.recording.SET_PAUSED"
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val EXTRA_PAUSED = "paused"

        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        var isPaused: Boolean = false

        /** Thread-safe buffer of recorded fixes (maps match Dart expectations). */
        val points: MutableList<Map<String, Any>> =
            Collections.synchronizedList(mutableListOf())

        fun clearPoints(context: Context) {
            points.clear()
            pointsFile(context).delete()
        }

        fun pointsFile(context: Context): File =
            File(context.filesDir, POINTS_FILE)
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private val fusedClient by lazy { LocationServices.getFusedLocationProviderClient(this) }
    private val locationCallback =
        object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                if (isPaused) return
                for (location in result.locations) {
                    val point =
                        mapOf(
                            "latitude" to location.latitude,
                            "longitude" to location.longitude,
                            "altitude" to location.altitude,
                            "speed" to location.speed.toDouble(),
                            "bearing" to location.bearing.toDouble(),
                            "timeMs" to location.time,
                            "accuracy" to location.accuracy.toDouble(),
                        )
                    points.add(point)
                    appendPointToFile(point)
                    RecordingNativeBridge.emitPoint(point)
                }
            }
        }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopRecordingInternal()
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_SET_PAUSED -> {
                isPaused = intent.getBooleanExtra(EXTRA_PAUSED, false)
                return START_STICKY
            }
            ACTION_START, null -> {
                val title = intent?.getStringExtra(EXTRA_TITLE) ?: "RideAtlas"
                val text = intent?.getStringExtra(EXTRA_TEXT) ?: "Recording your ride"
                if (!isRunning) {
                    // A null action means the system restarted this
                    // START_STICKY service after Android (or an aggressive
                    // OEM battery saver) killed the whole process mid-ride -
                    // the in-memory isRunning flag resets to false along
                    // with everything else, so this looks identical to a
                    // genuine fresh start. The two must NOT be treated the
                    // same: a real fresh start never has a leftover points
                    // file (both the normal "stop" and "discard" paths
                    // delete it themselves), so a file existing here means
                    // recording was interrupted before it could be. Recover
                    // it instead of wiping it - losing GPS history nobody
                    // asked to discard is exactly the bug this guards
                    // against.
                    if (pointsFile(this).exists()) {
                        reloadPointsFromFile()
                    } else {
                        clearPoints(this)
                    }
                    startAsForeground(title, text)
                    acquireWakeLock()
                    startLocationUpdates()
                    isRunning = true
                    isPaused = false
                } else {
                    // Already running - refresh the notification text if sent again.
                    startAsForeground(title, text)
                }
                return START_STICKY
            }
            else -> return START_NOT_STICKY
        }
    }

    override fun onDestroy() {
        stopRecordingInternal()
        super.onDestroy()
    }

    private fun stopRecordingInternal() {
        try {
            fusedClient.removeLocationUpdates(locationCallback)
        } catch (e: Exception) {
            Log.w(TAG, "removeLocationUpdates failed", e)
        }
        releaseWakeLock()
        isRunning = false
        isPaused = false
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    private fun startAsForeground(title: String, text: String) {
        ensureChannel()
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pending =
            PendingIntent.getActivity(
                this,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        val notification: Notification =
            NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(text)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentIntent(pending)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
            )
        } else {
            @Suppress("DEPRECATION")
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel =
            NotificationChannel(
                CHANNEL_ID,
                "RideAtlas recording",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Keeps GPS recording alive while the screen is off"
                setShowBadge(false)
            }
        manager.createNotificationChannel(channel)
    }

    private fun startLocationUpdates() {
        val request =
            LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 5_000L)
                .setMinUpdateIntervalMillis(2_000L)
                .setMinUpdateDistanceMeters(0f)
                .setWaitForAccurateLocation(false)
                .build()
        try {
            fusedClient.requestLocationUpdates(request, locationCallback, mainLooper)
        } catch (e: SecurityException) {
            Log.e(TAG, "Missing location permission", e)
            stopSelf()
        }
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock =
            pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "RideAtlas::Recording").apply {
                setReferenceCounted(false)
                acquire(6 * 60 * 60 * 1000L) // 6h max; stop() releases earlier
            }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {
        }
        wakeLock = null
    }

    private fun appendPointToFile(point: Map<String, Any>) {
        try {
            val json =
                JSONObject()
                    .put("latitude", point["latitude"])
                    .put("longitude", point["longitude"])
                    .put("altitude", point["altitude"])
                    .put("speed", point["speed"])
                    .put("bearing", point["bearing"])
                    .put("timeMs", point["timeMs"])
                    .put("accuracy", point["accuracy"])
            pointsFile(this).appendText(json.toString() + "\n")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to persist point", e)
        }
    }

    /** Restores [points] from the append-only file after the system
     * restarts this service post-kill (see the null-action branch of
     * [onStartCommand]) - the in-memory list is empty again on a fresh
     * process, but the file still has every fix collected before the kill. */
    private fun reloadPointsFromFile() {
        try {
            val restored = mutableListOf<Map<String, Any>>()
            pointsFile(this).forEachLine { line ->
                if (line.isBlank()) return@forEachLine
                val obj = JSONObject(line)
                restored.add(
                    mapOf(
                        "latitude" to obj.optDouble("latitude"),
                        "longitude" to obj.optDouble("longitude"),
                        "altitude" to obj.optDouble("altitude"),
                        "speed" to obj.optDouble("speed"),
                        "bearing" to obj.optDouble("bearing", 0.0),
                        "timeMs" to obj.optLong("timeMs"),
                        "accuracy" to obj.optDouble("accuracy"),
                    ),
                )
            }
            synchronized(points) {
                points.clear()
                points.addAll(restored)
            }
            Log.i(TAG, "Recovered ${restored.size} points from an interrupted recording")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to reload persisted points, starting fresh", e)
            clearPoints(this)
        }
    }
}
