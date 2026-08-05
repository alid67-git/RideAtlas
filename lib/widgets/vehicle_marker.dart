import 'package:flutter/material.dart';

import '../models/vehicle_icon.dart';

const _classicDotSize = 20.0;
const _imageMarkerBaseSize = 46.0;

/// The on-screen diameter [buildVehicleMarker] will render at for [option] -
/// callers need this up front to size the [Marker] widget that hosts it.
double vehicleMarkerSize(VehicleIconOption option) {
  if (option.imageAsset == null) return _classicDotSize;
  return _imageMarkerBaseSize * option.scale;
}

/// The "you are here" marker: either the classic blue dot, or the user's
/// chosen vehicle icon (see Settings > Araç ikonu) - a top-down photo of
/// the vehicle. Each color variant is its own pre-baked asset (see
/// vehicle_icon.dart) rather than a shared photo tinted at runtime.
Widget buildVehicleMarker(VehicleIconOption option) {
  final asset = option.imageAsset;
  if (asset == null) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blueAccent,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
      ),
    );
  }

  final size = vehicleMarkerSize(option);
  return DecoratedBox(
    decoration: const BoxDecoration(
      boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 6)],
    ),
    child: Image.asset(asset, width: size, height: size),
  );
}
