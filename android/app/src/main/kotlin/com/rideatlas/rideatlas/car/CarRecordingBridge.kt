package com.rideatlas.rideatlas.car

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Live recording state mirrored from Dart's GpsRecorder (see
 * lib/services/car_bridge.dart). Dart stays the single source of truth for
 * the actual recording; this object just caches the latest snapshot so the
 * Android Auto screen (RecordingScreen) can read it synchronously while
 * building its template, and re-renders itself via the registered
 * listeners whenever a fresh snapshot arrives.
 *
 * Also carries the [MethodChannel] itself, so button taps on the car
 * screen can call back into Dart (start/pause/resume/finish) the same way
 * state flows the other direction.
 */
object CarRecordingBridge {
    enum class State { IDLE, RECORDING, PAUSED }

    var state: State = State.IDLE
        private set
    var speedKmh: Double = 0.0
        private set
    var distanceKm: Double = 0.0
        private set
    var durationSeconds: Int = 0
        private set
    var altitudeMeters: Double? = null
        private set
    var isAutoPaused: Boolean = false
        private set

    private var channel: MethodChannel? = null
    private val listeners = mutableListOf<() -> Unit>()

    fun attach(channel: MethodChannel) {
        this.channel = channel
    }

    fun addListener(listener: () -> Unit) {
        listeners.add(listener)
    }

    fun removeListener(listener: () -> Unit) {
        listeners.remove(listener)
    }

    /** Applies a state snapshot pushed from Dart's "updateState" call. */
    fun handleUpdate(call: MethodCall) {
        state = when (call.argument<String>("state")) {
            "recording" -> State.RECORDING
            "paused" -> State.PAUSED
            else -> State.IDLE
        }
        speedKmh = (call.argument<Number>("speedKmh"))?.toDouble() ?: 0.0
        distanceKm = (call.argument<Number>("distanceKm"))?.toDouble() ?: 0.0
        durationSeconds = (call.argument<Number>("durationSeconds"))?.toInt() ?: 0
        altitudeMeters = (call.argument<Number>("altitudeMeters"))?.toDouble()
        isAutoPaused = call.argument<Boolean>("isAutoPaused") ?: false
        listeners.toList().forEach { it() }
    }

    fun start() {
        channel?.invokeMethod("start", null)
    }

    fun pause() {
        channel?.invokeMethod("pause", null)
    }

    fun resume() {
        channel?.invokeMethod("resume", null)
    }

    fun finish() {
        channel?.invokeMethod("finish", null)
    }
}
