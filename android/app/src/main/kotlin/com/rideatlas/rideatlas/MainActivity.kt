package com.rideatlas.rideatlas

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
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

class MainActivity : FlutterActivity() {

    // Created in configureFlutterEngine(), not as a field initializer:
    // applicationContext isn't available yet at construction time (Android
    // calls attachBaseContext() only after the Activity object exists).
    private var satelliteTracker: GnssSatelliteTracker? = null

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
        FlutterEngineCache.getInstance().remove(CAR_FLUTTER_ENGINE_ID)
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
