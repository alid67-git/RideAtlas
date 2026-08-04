import 'package:flutter/material.dart';

import '../models/vehicle_icon.dart';

const _classicDotSize = 20.0;
const _iconMarkerBaseSize = 30.0;

/// The on-screen diameter [buildVehicleMarker] will render at for [option] -
/// callers need this up front to size the [Marker] widget that hosts it.
double vehicleMarkerSize(VehicleIconOption option) {
  if (option.icon == null) return _classicDotSize;
  return _iconMarkerBaseSize * option.scale;
}

/// The "you are here" marker: either the classic blue dot, or the user's
/// chosen vehicle icon (see Settings > Araç ikonu).
Widget buildVehicleMarker(VehicleIconOption option) {
  if (option.icon == null) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blueAccent,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
      ),
    );
  }

  final size = vehicleMarkerSize(option);
  return Container(
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      border: Border.all(color: option.color!, width: 2),
      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
    ),
    child: Icon(option.icon, color: option.color, size: size * 0.62),
  );
}
