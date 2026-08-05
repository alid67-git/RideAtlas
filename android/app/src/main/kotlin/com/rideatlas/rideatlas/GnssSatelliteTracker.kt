package com.rideatlas.rideatlas

import android.content.Context
import android.location.GnssStatus
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper

/**
 * Tracks the number of GPS/GNSS satellites currently used in the position
 * fix (not just visible - that count is noisy and includes satellites too
 * weak to actually contribute) via a passive [GnssStatus.Callback], caching
 * the latest value for [MainActivity]'s method channel to hand to Dart on
 * request. Polling a cached value (rather than pushing it over an
 * EventChannel) sidesteps EventChannel.receiveBroadcastStream()'s
 * documented behavior of reporting a missing platform handler through
 * FlutterError instead of the stream itself, which is exactly the
 * situation Flutter's own widget-test harness is in (it has no native
 * platform to answer channel calls).
 *
 * GnssStatus.Callback needs API 24+; on older devices [lastUsedInFixCount]
 * simply never updates, which the Dart side treats as "unknown" (hides the
 * indicator).
 */
class GnssSatelliteTracker(context: Context) {

    @Volatile
    var lastUsedInFixCount: Int? = null
        private set

    init {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val locationManager =
                context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            try {
                locationManager?.registerGnssStatusCallback(
                    object : GnssStatus.Callback() {
                        override fun onSatelliteStatusChanged(status: GnssStatus) {
                            var usedInFix = 0
                            for (i in 0 until status.satelliteCount) {
                                if (status.usedInFix(i)) usedInFix++
                            }
                            lastUsedInFixCount = usedInFix
                        }
                    },
                    Handler(Looper.getMainLooper()),
                )
            } catch (e: SecurityException) {
                // No location permission yet - lastUsedInFixCount just stays
                // null until the user grants it and GPS starts producing
                // fixes through GpsRecorder/the live-location stream.
            }
        }
    }
}
