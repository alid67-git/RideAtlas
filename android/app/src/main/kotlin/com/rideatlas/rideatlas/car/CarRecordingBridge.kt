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
    var latitude: Double? = null
        private set
    var longitude: Double? = null
        private set
    var headingDegrees: Double? = null
        private set

    private const val MAX_TRAIL_POINTS = 2000

    /** Lat/lng pairs recorded so far this ride, for [CarMapRenderer] to draw
     * as a trail. Cleared whenever recording goes back to idle. */
    private val trail = mutableListOf<DoubleArray>()

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

    fun trailSnapshot(): List<DoubleArray> = synchronized(trail) { trail.toList() }

    /** Applies a state snapshot pushed from Dart's "updateState" call. */
    fun handleUpdate(call: MethodCall) {
        val newState = when (call.argument<String>("state")) {
            "recording" -> State.RECORDING
            "paused" -> State.PAUSED
            else -> State.IDLE
        }
        if (newState == State.IDLE && state != State.IDLE) {
            synchronized(trail) { trail.clear() }
        }
        state = newState
        speedKmh = (call.argument<Number>("speedKmh"))?.toDouble() ?: 0.0
        distanceKm = (call.argument<Number>("distanceKm"))?.toDouble() ?: 0.0
        durationSeconds = (call.argument<Number>("durationSeconds"))?.toInt() ?: 0
        altitudeMeters = (call.argument<Number>("altitudeMeters"))?.toDouble()
        isAutoPaused = call.argument<Boolean>("isAutoPaused") ?: false
        latitude = (call.argument<Number>("lat"))?.toDouble()
        longitude = (call.argument<Number>("lng"))?.toDouble()
        headingDegrees = (call.argument<Number>("headingDegrees"))?.toDouble()

        val lat = latitude
        val lng = longitude
        if (state != State.IDLE && lat != null && lng != null) {
            synchronized(trail) {
                val last = trail.lastOrNull()
                if (last == null || last[0] != lat || last[1] != lng) {
                    trail.add(doubleArrayOf(lat, lng))
                    if (trail.size > MAX_TRAIL_POINTS) trail.removeAt(0)
                }
            }
        }

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
