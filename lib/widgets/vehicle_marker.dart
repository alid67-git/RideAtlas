import 'package:flutter/material.dart';

import '../models/vehicle_icon.dart';

const _classicDotSize = 20.0;
const _iconMarkerBaseSize = 34.0;

/// The on-screen diameter [buildVehicleMarker] will render at for [option] -
/// callers need this up front to size the [Marker] widget that hosts it.
double vehicleMarkerSize(VehicleIconOption option) {
  if (option.emoji == null) return _classicDotSize;
  return _iconMarkerBaseSize * option.scale;
}

/// The "you are here" marker: either the classic blue dot, or the user's
/// chosen vehicle icon (see Settings > Araç ikonu) - a full-color vehicle
/// emoji over a colored circular badge.
Widget buildVehicleMarker(VehicleIconOption option) {
  if (option.emoji == null) {
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
      color: option.badgeColor,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2.5),
      boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 5)],
    ),
    alignment: Alignment.center,
    child: Text(
      option.emoji!,
      style: TextStyle(fontSize: size * 0.58),
    ),
  );
}
