package com.rideatlas.rideatlas.car

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.CarIcon
import androidx.car.app.model.Pane
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.car.app.navigation.model.NavigationTemplate
import androidx.core.graphics.drawable.IconCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.rideatlas.rideatlas.R

/**
 * The Android Auto surface for RideAtlas. Idle: a simple start button
 * (Pane). Recording/paused: a live, heading-up rotating map drawn directly
 * onto the car's surface by [renderer] (same course-up convention as
 * RecordScreen's own map - see lib/screens/record_screen.dart), with
 * pause/resume/finish as the template's action strip. Driver-distraction
 * rules rule out anything requiring text entry (like naming a ride) while
 * driving, so "Bitir" saves under an auto-generated name straight away, the
 * same default RecordScreen offers before a rider edits it by hand.
 */
class RecordingScreen(
    carContext: CarContext,
    private val renderer: CarMapRenderer,
) : Screen(carContext), DefaultLifecycleObserver {

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
        if (CarRecordingBridge.state == CarRecordingBridge.State.IDLE) {
            val pane =
                Pane.Builder()
                    .addRow(
                        Row.Builder()
                            .setTitle("RideAtlas")
                            .addText("Kayda başlamak için dokunun")
                            .build()
                    )
                    .addAction(
                        Action.Builder()
                            .setTitle("Kayda başla")
                            .setOnClickListener { CarRecordingBridge.start() }
                            .build()
                    )
                    .build()
            return PaneTemplate.Builder(pane)
                .setTitle("RideAtlas")
                .setHeaderAction(Action.APP_ICON)
                .build()
        }

        // Recording/paused: the map itself (including live stats) is drawn
        // straight onto the surface by [renderer] - see CarMapRenderer.
        // Only the action strip is built through the template API. Both
        // buttons are icon-only (no setTitle): NavigationTemplate's action
        // strip allows at most one action with a custom title, so an
        // icon-only pair sidesteps that limit entirely.
        val paused = CarRecordingBridge.state == CarRecordingBridge.State.PAUSED
        val actionStrip =
            ActionStrip.Builder()
                .addAction(
                    Action.Builder()
                        .setIcon(
                            CarIcon.Builder(
                                    IconCompat.createWithResource(
                                        carContext,
                                        if (paused) R.drawable.ic_car_play else R.drawable.ic_car_pause,
                                    )
                                )
                                .build()
                        )
                        .setOnClickListener {
                            if (paused) CarRecordingBridge.resume() else CarRecordingBridge.pause()
                        }
                        .build()
                )
                .addAction(
                    Action.Builder()
                        .setIcon(
                            CarIcon.Builder(
                                    IconCompat.createWithResource(carContext, R.drawable.ic_car_stop)
                                )
                                .build()
                        )
                        .setOnClickListener { CarRecordingBridge.finish() }
                        .build()
                )
                .build()

        renderer.redraw()
        return NavigationTemplate.Builder().setActionStrip(actionStrip).build()
    }
}
