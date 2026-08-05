package com.rideatlas.rideatlas

import com.rideatlas.rideatlas.car.CarRecordingBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/** Also used by [com.rideatlas.rideatlas.car.RideAtlasCarSession] to find
 * this Activity's Dart engine from outside the Activity lifecycle. */
const val CAR_FLUTTER_ENGINE_ID = "rideatlas_car_engine"
private const val CAR_METHOD_CHANNEL = "com.rideatlas.app/car"

class MainActivity : FlutterActivity() {

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
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        FlutterEngineCache.getInstance().remove(CAR_FLUTTER_ENGINE_ID)
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
