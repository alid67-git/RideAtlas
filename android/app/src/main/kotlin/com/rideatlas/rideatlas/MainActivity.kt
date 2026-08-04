package com.rideatlas.rideatlas

import android.content.Context
import com.rideatlas.rideatlas.car.CarRecordingBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/** Also used by [com.rideatlas.rideatlas.car.RideAtlasCarSession] to find
 * the same running Dart engine from outside the Activity lifecycle. */
const val CAR_FLUTTER_ENGINE_ID = "rideatlas_car_engine"
private const val CAR_METHOD_CHANNEL = "com.rideatlas.app/car"

class MainActivity : FlutterActivity() {

    // Android Auto's Session/Screen classes aren't Activities and can
    // outlive this one, so they need a Dart engine that isn't tied to this
    // Activity's lifecycle to talk to. Caching the engine here (instead of
    // letting FlutterActivity create-and-discard one per launch) means the
    // exact same engine - and the GpsRecorder/RouteRepository instances
    // living in its widget tree - is still reachable via
    // FlutterEngineCache from the car session as long as the app process
    // is alive, whether or not this Activity is currently on screen.
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        FlutterEngineCache.getInstance().get(CAR_FLUTTER_ENGINE_ID)?.let { return it }
        val engine = FlutterEngine(context)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(CAR_FLUTTER_ENGINE_ID, engine)
        return engine
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
}
