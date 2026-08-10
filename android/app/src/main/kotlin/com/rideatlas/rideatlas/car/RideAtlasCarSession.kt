package com.rideatlas.rideatlas.car

import android.content.Intent
import androidx.car.app.Screen
import androidx.car.app.Session

class RideAtlasCarSession : Session() {
    private var mapRenderer: CarMapRenderer? = null

    override fun onCreateScreen(intent: Intent): Screen {
        val renderer =
            mapRenderer ?: CarMapRenderer(carContext).also { newRenderer ->
                newRenderer.attach()
                CarRecordingBridge.addListener { newRenderer.redraw() }
                mapRenderer = newRenderer
            }
        return RecordingScreen(carContext, renderer)
    }
}
