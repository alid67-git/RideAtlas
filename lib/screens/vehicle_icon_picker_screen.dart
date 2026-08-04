import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/vehicle_icon.dart';
import '../repositories/vehicle_icon_controller.dart';
import '../widgets/vehicle_marker.dart';

/// Picks the "you are here" marker style: the classic dot, or one of five
/// scale/color presets each for motorcycle and car. The choice is persisted
/// by [VehicleIconController] and stays until changed here again.
class VehicleIconPickerScreen extends StatelessWidget {
  const VehicleIconPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = context.watch<VehicleIconController>();
    final current = controller.option;

    Widget sectionTitle(String text) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    Widget optionTile(VehicleIconOption option, String label) {
      final selected = option.id == current.id;
      return ListTile(
        leading: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: SizedBox(
              width: vehicleMarkerSize(option),
              height: vehicleMarkerSize(option),
              child: buildVehicleMarker(option),
            ),
          ),
        ),
        title: Text(label),
        trailing: selected ? const Icon(Icons.check) : null,
        selected: selected,
        onTap: () => controller.setOption(option),
      );
    }

    final motoOptions = kVehicleIconOptions
        .where((o) => o.category == VehicleIconCategory.motorcycle)
        .toList();
    final carOptions = kVehicleIconOptions
        .where((o) => o.category == VehicleIconCategory.car)
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.vehicleIconTitle)),
      body: ListView(
        children: [
          optionTile(kVehicleIconOptions.first, l10n.vehicleIconClassic),
          const Divider(height: 1),
          sectionTitle(l10n.vehicleIconMotorcycleCategory),
          for (var i = 0; i < motoOptions.length; i++)
            optionTile(motoOptions[i], l10n.vehicleIconOptionLabel(i + 1)),
          const Divider(height: 1),
          sectionTitle(l10n.vehicleIconCarCategory),
          for (var i = 0; i < carOptions.length; i++)
            optionTile(carOptions[i], l10n.vehicleIconOptionLabel(i + 1)),
        ],
      ),
    );
  }
}
