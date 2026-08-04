package com.rideatlas.rideatlas.car

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.Pane
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import java.util.Locale
import kotlin.math.roundToInt

/**
 * The whole Android Auto surface for RideAtlas: no map, no navigation
 * guidance - just the live stats a rider already sees in-app (speed,
 * duration, distance) plus start/pause/resume/finish. Driver-distraction
 * rules rule out anything requiring text entry (like naming a ride) while
 * driving, so "Bitir" saves under an auto-generated name straight away,
 * the same default RecordScreen offers before a rider edits it by hand.
 */
class RecordingScreen(carContext: CarContext) : Screen(carContext), DefaultLifecycleObserver {

    private val onBridgeUpdate: () -> Unit = { invalidate() }

    init {
        lifecycle.addObserver(this)
    }

    override fun onStart(owner: LifecycleOwner) {
        CarRecordingBridge.addListener(onBridgeUpdate)
    }

    override fun onStop(owner: LifecycleOwner) {
        CarRecordingBridge.removeListener(onBridgeUpdate)
    }

    override fun onGetTemplate(): Template {
        val pane = Pane.Builder()

        if (CarRecordingBridge.state == CarRecordingBridge.State.IDLE) {
            pane.addRow(
                Row.Builder()
                    .setTitle("RideAtlas")
                    .addText("Kayda başlamak için dokunun")
                    .build()
            )
            pane.addAction(
                Action.Builder()
                    .setTitle("Kayda başla")
                    .setOnClickListener { CarRecordingBridge.start() }
                    .build()
            )
        } else {
            val paused = CarRecordingBridge.state == CarRecordingBridge.State.PAUSED
            pane.addRow(
                Row.Builder()
                    .setTitle("${CarRecordingBridge.speedKmh.roundToInt()} km/s")
                    .addText(
                        when {
                            CarRecordingBridge.isAutoPaused -> "Otomatik duraklatıldı"
                            paused -> "Duraklatıldı"
                            else -> "Kayıt sürüyor"
                        }
                    )
                    .build()
            )
            pane.addRow(
                Row.Builder()
                    .setTitle("Süre: ${formatDuration(CarRecordingBridge.durationSeconds)}")
                    .addText(
                        String.format(
                            Locale.getDefault(),
                            "Mesafe: %.2f km",
                            CarRecordingBridge.distanceKm
                        )
                    )
                    .build()
            )
            pane.addAction(
                Action.Builder()
                    .setTitle(if (paused) "Devam et" else "Duraklat")
                    .setOnClickListener {
                        if (paused) CarRecordingBridge.resume() else CarRecordingBridge.pause()
                    }
                    .build()
            )
            pane.addAction(
                Action.Builder()
                    .setTitle("Bitir")
                    .setOnClickListener { CarRecordingBridge.finish() }
                    .build()
            )
        }

        return PaneTemplate.Builder(pane.build())
            .setTitle("RideAtlas")
            .setHeaderAction(Action.APP_ICON)
            .build()
    }

    private fun formatDuration(totalSeconds: Int): String {
        val h = totalSeconds / 3600
        val m = (totalSeconds % 3600) / 60
        val s = totalSeconds % 60
        return if (h > 0) {
            String.format(Locale.getDefault(), "%d:%02d:%02d", h, m, s)
        } else {
            String.format(Locale.getDefault(), "%02d:%02d", m, s)
        }
    }
}
