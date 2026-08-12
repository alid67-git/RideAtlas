enum VehicleIconCategory { classic, motorcycle, car }

/// Size multipliers the vehicle icon picker offers - same 5-step scale as
/// the stat card icon settings, so both "size" pickers in the app behave
/// the same way.
const vehicleIconSizeOptions = <double>[0.8, 1.0, 1.2, 1.4, 1.6];

/// A selectable icon for the "you are here" marker on the map. [classic]
/// (the plain blue dot) has no image/scale - those only apply to the
/// motorcycle/car options, which render a real top-down vehicle photo
/// (`assets/vehicles/`).
///
/// Each color variant is its own pre-baked PNG (recolored offline, not at
/// runtime): `ColorFiltered`/`BlendMode.color` looked identical in this
/// app's own preview tooling, but on-device it bled its tint across the
/// *entire* render layer on some Android GPUs (the whole screen, not just
/// the marker, turned solid purple) - a known category of Skia issue with
/// the HSL blend modes. Baking the color into the pixels themselves
/// sidesteps that runtime rendering path entirely.
class VehicleIconOption {
  const VehicleIconOption({
    required this.id,
    required this.category,
    this.imageAsset,
    this.scale = 1.0,
  });

  final String id;
  final VehicleIconCategory category;
  final String? imageAsset;

  /// Multiplier applied to the marker's base size.
  final double scale;
}

const kVehicleIconOptions = <VehicleIconOption>[
  VehicleIconOption(id: 'classic', category: VehicleIconCategory.classic),

  VehicleIconOption(
    id: 'moto_1',
    category: VehicleIconCategory.motorcycle,
    imageAsset: 'assets/vehicles/moto_1.png',
    scale: 0.8,
  ),
  VehicleIconOption(
    id: 'moto_2',
    category: VehicleIconCategory.motorcycle,
    imageAsset: 'assets/vehicles/moto_2.png',
    scale: 1.0,
  ),
  VehicleIconOption(
    id: 'moto_3',
    category: VehicleIconCategory.motorcycle,
    imageAsset: 'assets/vehicles/moto_3.png',
    scale: 1.2,
  ),
  VehicleIconOption(
    id: 'moto_4',
    category: VehicleIconCategory.motorcycle,
    imageAsset: 'assets/vehicles/moto_4.png',
    scale: 1.0,
  ),
  VehicleIconOption(
    id: 'moto_5',
    category: VehicleIconCategory.motorcycle,
    imageAsset: 'assets/vehicles/moto_5.png',
    scale: 1.4,
  ),

  VehicleIconOption(
    id: 'car_1',
    category: VehicleIconCategory.car,
    imageAsset: 'assets/vehicles/car_1.png',
    scale: 0.8,
  ),
  VehicleIconOption(
    id: 'car_2',
    category: VehicleIconCategory.car,
    imageAsset: 'assets/vehicles/car_2.png',
    scale: 1.0,
  ),
  VehicleIconOption(
    id: 'car_3',
    category: VehicleIconCategory.car,
    imageAsset: 'assets/vehicles/car_3.png',
    scale: 1.2,
  ),
  VehicleIconOption(
    id: 'car_4',
    category: VehicleIconCategory.car,
    imageAsset: 'assets/vehicles/car_4.png',
    scale: 1.0,
  ),
  VehicleIconOption(
    id: 'car_5',
    category: VehicleIconCategory.car,
    imageAsset: 'assets/vehicles/car_5.png',
    scale: 1.4,
  ),
];

VehicleIconOption findVehicleIconOption(String? id) {
  return kVehicleIconOptions.firstWhere(
    (o) => o.id == id,
    orElse: () => kVehicleIconOptions.first,
  );
}
