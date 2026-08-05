import 'package:flutter/material.dart';

enum VehicleIconCategory { classic, motorcycle, car }

/// A selectable icon for the "you are here" marker on the map. [classic]
/// (the plain blue dot) has no image/tint/scale - those only apply to the
/// motorcycle/car options, which render a real top-down vehicle photo
/// (`assets/vehicles/`) recolored via a hue/saturation tint - see
/// [buildVehicleMarker] - so the same photo can offer several color
/// variants without needing separate art per color.
class VehicleIconOption {
  const VehicleIconOption({
    required this.id,
    required this.category,
    this.imageAsset,
    this.tintColor,
    this.scale = 1.0,
  });

  final String id;
  final VehicleIconCategory category;
  final String? imageAsset;
  final Color? tintColor;

  /// Multiplier applied to the marker's base size.
  final double scale;
}

const _motorcycleAsset = 'assets/vehicles/motorcycle.png';
const _carAsset = 'assets/vehicles/car.png';

const kVehicleIconOptions = <VehicleIconOption>[
  VehicleIconOption(id: 'classic', category: VehicleIconCategory.classic),

  VehicleIconOption(
    id: 'moto_1',
    category: VehicleIconCategory.motorcycle,
    imageAsset: _motorcycleAsset,
    tintColor: Color(0xFFE53935),
    scale: 0.8,
  ),
  VehicleIconOption(
    id: 'moto_2',
    category: VehicleIconCategory.motorcycle,
    imageAsset: _motorcycleAsset,
    tintColor: Color(0xFF1E88E5),
    scale: 1.0,
  ),
  VehicleIconOption(
    id: 'moto_3',
    category: VehicleIconCategory.motorcycle,
    imageAsset: _motorcycleAsset,
    tintColor: Color(0xFF43A047),
    scale: 1.2,
  ),
  VehicleIconOption(
    id: 'moto_4',
    category: VehicleIconCategory.motorcycle,
    imageAsset: _motorcycleAsset,
    tintColor: Color(0xFFFB8C00),
    scale: 1.0,
  ),
  VehicleIconOption(
    id: 'moto_5',
    category: VehicleIconCategory.motorcycle,
    imageAsset: _motorcycleAsset,
    tintColor: Color(0xFF8E24AA),
    scale: 1.4,
  ),

  VehicleIconOption(
    id: 'car_1',
    category: VehicleIconCategory.car,
    imageAsset: _carAsset,
    tintColor: Color(0xFFE53935),
    scale: 0.8,
  ),
  VehicleIconOption(
    id: 'car_2',
    category: VehicleIconCategory.car,
    imageAsset: _carAsset,
    tintColor: Color(0xFF1E88E5),
    scale: 1.0,
  ),
  VehicleIconOption(
    id: 'car_3',
    category: VehicleIconCategory.car,
    imageAsset: _carAsset,
    tintColor: Color(0xFF43A047),
    scale: 1.2,
  ),
  VehicleIconOption(
    id: 'car_4',
    category: VehicleIconCategory.car,
    imageAsset: _carAsset,
    tintColor: Color(0xFFFB8C00),
    scale: 1.0,
  ),
  VehicleIconOption(
    id: 'car_5',
    category: VehicleIconCategory.car,
    imageAsset: _carAsset,
    tintColor: Color(0xFF8E24AA),
    scale: 1.4,
  ),
];

VehicleIconOption findVehicleIconOption(String? id) {
  return kVehicleIconOptions.firstWhere(
    (o) => o.id == id,
    orElse: () => kVehicleIconOptions.first,
  );
}
