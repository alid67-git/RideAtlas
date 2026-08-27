import 'package:flutter/material.dart';

import '../models/vehicle_icon.dart';

/// Compact on-map footprint - large enough to tap, small enough not to
/// cover a country at world zoom the way the old ~46–74px badges did.
const _classicDotSize = 16.0;
const _imageMarkerBaseSize = 30.0;

/// The on-screen diameter [buildVehicleMarker] will render at for [option] -
/// callers need this up front to size the [Marker] widget that hosts it.
double vehicleMarkerSize(VehicleIconOption option) {
  if (option.imageAsset == null) return _classicDotSize;
  return _imageMarkerBaseSize * option.scale;
}

/// The "you are here" marker: either the classic blue dot, or the user's
/// chosen vehicle icon (see Settings > Araç ikonu).
///
/// Kept small, but with a hard white rim + dark shadow so it stays readable
/// on satellite tiles instead of either dominating the map or vanishing
/// into the imagery.
Widget buildVehicleMarker(VehicleIconOption option) {
  final asset = option.imageAsset;
  if (asset == null) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E88E5),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0xB3000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
          BoxShadow(
            color: Color(0x991E88E5),
            blurRadius: 7,
            spreadRadius: 0.5,
          ),
        ],
      ),
    );
  }

  final size = vehicleMarkerSize(option);
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: const Color(0xFFFF6D00),
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: const [
        BoxShadow(
          color: Color(0xB3000000),
          blurRadius: 3.5,
          offset: Offset(0, 1),
        ),
        BoxShadow(
          color: Color(0x99FF6D00),
          blurRadius: 8,
          spreadRadius: 0.5,
        ),
      ],
    ),
    padding: const EdgeInsets.all(2.5),
    child: ClipOval(
      child: ColoredBox(
        color: Colors.white,
        child: Image.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
    ),
  );
}
