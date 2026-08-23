package com.rideatlas.rideatlas

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Dart ↔ native bridge for [RecordingLocationService]. Location fixes are
 * collected natively so they survive screen-off; Flutter only consumes them.
 */
object RecordingNativeBridge {
    const val METHOD_CHANNEL = "com.rideatlas.app/recording"
    const val EVENT_CHANNEL = "com.rideatlas.app/recording_events"
    private const val NOTIFICATION_PERMISSION_REQ = 4811

    private var appContext: Context? = null
    private var activity: Activity? = null
    private var eventSink: EventChannel.EventSink? = null

    fun attach(context: Context, activity: Activity, messenger: io.flutter.plugin.common.BinaryMessenger) {
        appContext = context.applicationContext
        this.activity = activity

        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            handleMethod(call, result)
        }
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            },
        )
    }

    fun detach() {
        eventSink = null
        activity = null
    }

    fun emitPoint(point: Map<String, Any>) {
        // May be called from the main looper of the service; EventSink is
        // not thread-safe across isolates, so hop to the activity's UI thread
        // when we have one. If Flutter is frozen, the sink is typically null
        // and the point still lives in RecordingLocationService.points.
        val act = activity
        if (act != null) {
            act.runOnUiThread {
                try {
                    eventSink?.success(point)
                } catch (_: Exception) {
                }
            }
        } else {
            try {
                eventSink?.success(point)
            } catch (_: Exception) {
            }
        }
    }

    private fun handleMethod(call: MethodCall, result: MethodChannel.Result) {
        val ctx = appContext
        if (ctx == null) {
            result.error("no_context", "Bridge not attached", null)
            return
        }
        when (call.method) {
            "start" -> {
                val title = call.argument<String>("title") ?: "RideAtlas"
                val text = call.argument<String>("text") ?: "Recording your ride"
                val startedAtMs = call.argument<Number>("startedAtMs")?.toLong()
                    ?: System.currentTimeMillis()
                val manualPaused = call.argument<Boolean>("manualPaused") ?: false
                val batteryStart = call.argument<Number>("batteryStartPercent")?.toInt()
                ensureNotificationPermission()
                val intent =
                    Intent(ctx, RecordingLocationService::class.java).apply {
                        action = RecordingLocationService.ACTION_START
                        putExtra(RecordingLocationService.EXTRA_TITLE, title)
                        putExtra(RecordingLocationService.EXTRA_TEXT, text)
                        putExtra(RecordingLocationService.EXTRA_STARTED_AT_MS, startedAtMs)
                        putExtra(RecordingLocationService.EXTRA_MANUAL_PAUSED, manualPaused)
                        if (batteryStart != null) {
                            putExtra(RecordingLocationService.EXTRA_BATTERY_START, batteryStart)
                        }
                    }
                ContextCompat.startForegroundService(ctx, intent)
                result.success(true)
            }
            "stop" -> {
                val snapshot = snapshotPoints()
                val intent =
                    Intent(ctx, RecordingLocationService::class.java).apply {
                        action = RecordingLocationService.ACTION_STOP
                    }
                ctx.startService(intent)
                RecordingLocationService.clearPoints(ctx)
                result.success(snapshot)
            }
            "setPaused" -> {
                val paused = call.argument<Boolean>("paused") ?: false
                val manualPaused = call.argument<Boolean>("manualPaused")
                RecordingLocationService.isPaused = paused
                if (RecordingLocationService.isRunning) {
                    val intent =
                        Intent(ctx, RecordingLocationService::class.java).apply {
                            action = RecordingLocationService.ACTION_SET_PAUSED
                            putExtra(RecordingLocationService.EXTRA_PAUSED, paused)
                            if (manualPaused != null) {
                                putExtra(
                                    RecordingLocationService.EXTRA_MANUAL_PAUSED,
                                    manualPaused,
                                )
                            }
                        }
                    ctx.startService(intent)
                } else {
                    RecordingLocationService.updateSessionPauseFlags(
                        ctx,
                        nativePaused = paused,
                        manualPaused = manualPaused,
                    )
                }
                result.success(null)
            }
            "getPoints" -> result.success(snapshotPoints())
            "getPointsSince" -> {
                val index = call.argument<Int>("index") ?: 0
                val all = snapshotPoints()
                result.success(if (index <= 0) all else all.drop(index))
            }
            "isRunning" -> result.success(RecordingLocationService.isRunning)
            "getSession" -> result.success(RecordingLocationService.readSession(ctx))
            "saveSession" -> {
                val startedAtMs = call.argument<Number>("startedAtMs")?.toLong()
                    ?: System.currentTimeMillis()
                val manualPaused = call.argument<Boolean>("manualPaused") ?: false
                val nativePaused = call.argument<Boolean>("nativePaused") ?: false
                val title = call.argument<String>("title") ?: "RideAtlas"
                val text = call.argument<String>("text") ?: "Recording your ride"
                val batteryStart = call.argument<Number>("batteryStartPercent")?.toInt()
                val pauseStartedAtMs = call.argument<Number>("pauseStartedAtMs")?.toLong()
                val rawPauses =
                    call.argument<List<*>>("completedPauses") ?: emptyList<Any?>()
                val pauses =
                    rawPauses.mapNotNull { item ->
                        val p = item as? Map<*, *> ?: return@mapNotNull null
                        mapOf(
                            "durationMs" to ((p["durationMs"] as? Number)?.toLong() ?: 0L),
                            "endMs" to ((p["endMs"] as? Number)?.toLong() ?: 0L),
                        )
                    }
                RecordingLocationService.writeSession(
                    context = ctx,
                    startedAtMs = startedAtMs,
                    manualPaused = manualPaused,
                    nativePaused = nativePaused,
                    title = title,
                    text = text,
                    batteryStartPercent = batteryStart,
                    pauseStartedAtMs = pauseStartedAtMs,
                    completedPauses = pauses,
                )
                result.success(null)
            }
            "hasInterruptedSession" -> {
                val hasSession = RecordingLocationService.sessionFile(ctx).exists()
                val hasPoints = RecordingLocationService.pointsFile(ctx).exists()
                result.success(
                    RecordingLocationService.isRunning || hasSession || hasPoints,
                )
            }
            "getOrphanedPoints" -> {
                // Points left on disk from a recording the app never got to
                // stop/discard itself - both of those paths clean up their
                // own file, so a leftover one (while nothing is currently
                // running) means the process was killed mid-ride. See
                // RecordingLocationService.onStartCommand's null-action
                // comment for the restart-vs-fresh-start distinction this
                // relies on.
                if (RecordingLocationService.isRunning) {
                    result.success(emptyList<Map<String, Any>>())
                } else {
                    result.success(RecordingLocationService.readPointsFromFile(ctx))
                }
            }
            "clearOrphanedPoints" -> {
                RecordingLocationService.clearPoints(ctx)
                result.success(null)
            }
            "discard" -> {
                val intent =
                    Intent(ctx, RecordingLocationService::class.java).apply {
                        action = RecordingLocationService.ACTION_STOP
                    }
                ctx.startService(intent)
                RecordingLocationService.clearPoints(ctx)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun snapshotPoints(): List<Map<String, Any>> {
        synchronized(RecordingLocationService.points) {
            return ArrayList(RecordingLocationService.points)
        }
    }

    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val act = activity ?: return
        val granted =
            ContextCompat.checkSelfPermission(act, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        if (!granted) {
            ActivityCompat.requestPermissions(
                act,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQ,
            )
        }
    }
}
