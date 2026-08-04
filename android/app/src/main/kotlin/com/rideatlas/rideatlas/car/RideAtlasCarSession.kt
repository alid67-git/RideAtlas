package com.rideatlas.rideatlas.car

import android.content.Intent
import androidx.car.app.Screen
import androidx.car.app.Session

class RideAtlasCarSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen {
        return RecordingScreen(carContext)
    }
}
