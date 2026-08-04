package com.rideatlas.rideatlas.car

import androidx.car.app.CarAppService
import androidx.car.app.Session
import androidx.car.app.validation.HostValidator

class RideAtlasCarAppService : CarAppService() {

    // RideAtlas is sideloaded for personal use, not published to the Play
    // Store, so there's no Google-provided allowlist resource to point at
    // (that's normally generated as part of a Play listing). Google's
    // guidance is to only use ALLOW_ALL_HOSTS_VALIDATOR in debug builds,
    // but the alternative here is an allowlist with no legitimate values -
    // the only host that will ever actually connect is this device's own
    // Android Auto / Automotive projection.
    override fun createHostValidator(): HostValidator = HostValidator.ALLOW_ALL_HOSTS_VALIDATOR

    override fun onCreateSession(): Session = RideAtlasCarSession()
}
