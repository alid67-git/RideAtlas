import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/vehicle_icon.dart';
import '../repositories/vehicle_icon_controller.dart';
import '../widgets/vehicle_marker.dart';

/// Picks the "you are here" marker: the classic dot, or a motorcycle/car
/// with its own color and size chosen independently of each other (rather
/// than the old fixed color+size combos) - same picker pattern as
/// Settings > İstatistik ikon görünümü.
class VehicleIconPickerScreen extends StatelessWidget {
  const VehicleIconPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = context.watch<VehicleIconController>();
    final option = controller.option;
    final theme = Theme.of(context);

    Widget sectionTitle(String text) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.vehicleIconTitle)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Center(
              child: SizedBox(
                width: 60,
                height: 60,
                child: Center(
                  child: SizedBox(
                    width: vehicleMarkerSize(option),
                    height: vehicleMarkerSize(option),
                    child: buildVehicleMarker(option),
                  ),
                ),
              ),
            ),
          ),
          sectionTitle(l10n.vehicleIconTitle),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text(l10n.vehicleIconClassic),
                  selected: controller.category == VehicleIconCategory.classic,
                  onSelected: (_) =>
                      controller.setCategory(VehicleIconCategory.classic),
                ),
                ChoiceChip(
                  label: Text(l10n.vehicleIconMotorcycleCategory),
                  selected:
                      controller.category == VehicleIconCategory.motorcycle,
                  onSelected: (_) =>
                      controller.setCategory(VehicleIconCategory.motorcycle),
                ),
                ChoiceChip(
                  label: Text(l10n.vehicleIconCarCategory),
                  selected: controller.category == VehicleIconCategory.car,
                  onSelected: (_) =>
                      controller.setCategory(VehicleIconCategory.car),
                ),
              ],
            ),
          ),
          if (controller.category != VehicleIconCategory.classic) ...[
            sectionTitle(l10n.statIconColorLabel),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (var i = 0; i < controller.colorVariants.length; i++)
                    _VehicleColorSwatch(
                      asset: controller.colorVariants[i].imageAsset!,
                      label: l10n.vehicleIconOptionLabel(i + 1),
                      selected: i == controller.colorIndex,
                      onTap: () => controller.setColorIndex(i),
                    ),
                ],
              ),
            ),
            sectionTitle(l10n.statIconSizeLabel),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < vehicleIconSizeOptions.length; i++)
                    ChoiceChip(
                      label: Text(
                        '${(vehicleIconSizeOptions[i] * 100).round()}%',
                      ),
                      selected: i == controller.sizeIndex,
                      onSelected: (_) => controller.setSizeIndex(i),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _VehicleColorSwatch extends StatelessWidget {
  const _VehicleColorSwatch({
    required this.asset,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String asset;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(asset, width: 40, height: 40),
            const SizedBox(height: 4),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
