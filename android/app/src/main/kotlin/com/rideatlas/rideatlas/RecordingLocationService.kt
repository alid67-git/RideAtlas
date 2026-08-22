package com.rideatlas.rideatlas

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.location.Location
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.location.LocationCompat
import androidx.core.location.altitude.AltitudeConverterCompat
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import org.json.JSONObject
import java.io.File
import java.util.Collections
import java.util.concurrent.Executors

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

        /** Parses the append-only points file without touching [points] or
         * [isRunning] - used both by the resume-after-restart path below and
         * by [RecordingNativeBridge]'s orphan-recovery check, which must be
         * able to inspect a leftover file while nothing is running. */
        fun readPointsFromFile(context: Context): List<Map<String, Any>> {
            val restored = mutableListOf<Map<String, Any>>()
            try {
                pointsFile(context).forEachLine { line ->
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
            } catch (e: Exception) {
                Log.w(TAG, "Failed to read persisted points", e)
            }
            return restored
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private val fusedClient by lazy { LocationServices.getFusedLocationProviderClient(this) }

    // AltitudeConverterCompat.addMslAltitudeToLocation is @WorkerThread (loads
    // geoid assets / may hit Room). Location callbacks arrive on the main
    // looper, so convert off-thread before publishing the point to Dart.
    private val altitudeExecutor = Executors.newSingleThreadExecutor()

    private val locationCallback =
        object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                // Copy before handing off - the LocationResult batch is only
                // valid for the duration of this callback.
                val batch = ArrayList(result.locations)
                altitudeExecutor.execute {
                    for (location in batch) {
                        val point =
                            mapOf(
                                "latitude" to location.latitude,
                                "longitude" to location.longitude,
                                "altitude" to resolveMslAltitudeMeters(location),
                                "speed" to location.speed.toDouble(),
                                "bearing" to location.bearing.toDouble(),
                                "timeMs" to location.time,
                                "accuracy" to location.accuracy.toDouble(),
                            )
                        // The actual root cause of auto-pause never clearing by
                        // itself: this used to `return` entirely while paused,
                        // so NO fix ever reached Dart during a pause - the
                        // speed check that's supposed to notice the rider
                        // moving off again literally never ran (GpsRecorder's
                        // _onPosition was never called at all). Manually
                        // pausing/resuming "worked" only because that path sets
                        // the state directly, bypassing this stream entirely.
                        // Still keep paused fixes out of the persisted/recorded
                        // track and the restart-recovery file - GpsRecorder
                        // itself already excludes them from the saved route
                        // (see the _isAutoPaused branch in _onPosition), this
                        // just also skips writing them to disk here.
                        if (!isPaused) {
                            points.add(point)
                            appendPointToFile(point)
                        }
                        RecordingNativeBridge.emitPoint(point)
                    }
                }
            }
        }

    /**
     * Phone GPS reports height above the WGS84 ellipsoid via
     * [Location.getAltitude]. Riders expect Mean Sea Level (orthometric)
     * height - the two differ by the local geoid undulation, commonly
     * ~20–40 m, which showed up as "rakım ~25 m düşük". Prefer an
     * already-filled MSL value when the provider/OS supplies one; otherwise
     * convert with [AltitudeConverterCompat]. Falls back to ellipsoid height
     * if conversion fails so recording never stalls.
     */
    private fun resolveMslAltitudeMeters(location: Location): Double {
        if (!location.hasAltitude()) return location.altitude
        if (LocationCompat.hasMslAltitude(location)) {
            return LocationCompat.getMslAltitudeMeters(location)
        }
        return try {
            AltitudeConverterCompat.addMslAltitudeToLocation(this, location)
            if (LocationCompat.hasMslAltitude(location)) {
                LocationCompat.getMslAltitudeMeters(location)
            } else {
                location.altitude
            }
        } catch (e: Exception) {
            Log.w(TAG, "MSL altitude conversion failed; using ellipsoid height", e)
            location.altitude
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
                val newPaused = intent.getBooleanExtra(EXTRA_PAUSED, false)
                val changed = newPaused != isPaused
                isPaused = newPaused
                // Re-request updates at the paused/active cadence - the
                // foreground service + wake lock otherwise keep the GPS
                // chip working at full rate the whole ride regardless of
                // whether a rider is actually moving, which was needlessly
                // draining battery every time the ride auto-paused at a
                // light or a stop.
                if (changed && isRunning) startLocationUpdates()
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
                    // Set before startLocationUpdates() so a fresh start
                    // always begins at the active/fast cadence, even if a
                    // previous run crashed mid-pause and left the flag true.
                    isPaused = false
                    startAsForeground(title, text)
                    acquireWakeLock()
                    startLocationUpdates()
                    isRunning = true
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
        altitudeExecutor.shutdownNow()
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
        // Re-requesting with the same callback replaces whatever request
        // was previously registered for it - used both for the initial
        // start and to swap cadence when [isPaused] changes.
        val request = buildLocationRequest(isPaused)
        try {
            fusedClient.requestLocationUpdates(request, locationCallback, mainLooper)
        } catch (e: SecurityException) {
            Log.e(TAG, "Missing location permission", e)
            stopSelf()
        }
    }

    /**
     * Active: was 5s/2s - riders reported the displayed speed feeling very
     * delayed, which traces straight back to this interval: the
     * current-speed figure on screen can only refresh as often as a new fix
     * arrives. 1s (matching a typical navigation app) makes it track real
     * acceleration/deceleration promptly.
     *
     * Paused (manual or auto): nothing is being recorded, so there's no
     * reason to keep pulling high-accuracy fixes every second - this was
     * draining battery identically whether a rider was actually moving or
     * sitting at a light. A slower, lower-power request still delivers
     * occasional fixes so auto-pause can detect the ride resuming, just
     * without the same battery cost while stationary.
     *
     * Was 8s, but that meant up to 8s of riding with the map still showing
     * "Otomatik duraklatıldı" before a fix arrived to notice the rider had
     * actually moved off again - too laggy to ride with. 3s (matching
     * GpsRecorder's own stationary-detection delay before entering pause in
     * the first place) keeps that resume latency tolerable while still
     * cutting fix frequency to a third of the active rate.
     *
     * Priority was also PRIORITY_BALANCED_POWER_ACCURACY while paused, which
     * lets Play Services substitute WiFi/cell-tower positioning for the GPS
     * chip - those fixes commonly report speed 0 (no Doppler data), so once
     * a rider actually pulled away the smoothed speed could sit near zero
     * indefinitely and auto-pause never cleared ("takılı kalıyor", not just
     * slow to notice). Kept at PRIORITY_HIGH_ACCURACY so paused fixes still
     * come from the GPS chip with real speed - the interval alone (not the
     * priority) is what saves battery here, since the chip can duty-cycle
     * down between fixes either way.
     */
    private fun buildLocationRequest(paused: Boolean): LocationRequest =
        if (paused) {
            LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 3_000L)
                .setMinUpdateIntervalMillis(3_000L)
                .setWaitForAccurateLocation(false)
                .build()
        } else {
            LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 1_000L)
                .setMinUpdateIntervalMillis(500L)
                .setMinUpdateDistanceMeters(0f)
                .setWaitForAccurateLocation(false)
                .build()
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
        val restored = readPointsFromFile(this)
        synchronized(points) {
            points.clear()
            points.addAll(restored)
        }
        Log.i(TAG, "Recovered ${restored.size} points from an interrupted recording")
    }
}
