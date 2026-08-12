import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../repositories/stat_icon_settings_controller.dart';

/// Lets the rider pick the color and size used for every stat card icon
/// across the app (record screen, saved-route summary, analysis sheet),
/// instead of that being decided per screen in code.
class StatIconSettingsScreen extends StatelessWidget {
  const StatIconSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = context.watch<StatIconSettingsController>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.statIconSettingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Center(
              child: Icon(
                Icons.route,
                color: controller.color,
                size: 26 * controller.sizeScale,
              ),
            ),
          ),
          Text(
            l10n.statIconColorLabel,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var i = 0; i < statIconColorOptions.length; i++)
                _ColorSwatch(
                  color: statIconColorOptions[i],
                  selected: i == controller.colorIndex,
                  onTap: () => controller.setColorIndex(i),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            l10n.statIconSizeLabel,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < statIconSizeOptions.length; i++)
                ChoiceChip(
                  label: Text('${(statIconSizeOptions[i] * 100).round()}%'),
                  selected: i == controller.sizeIndex,
                  onSelected: (_) => controller.setSizeIndex(i),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.onSurface,
                  width: 3,
                )
              : null,
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 20)
            : null,
      ),
    );
  }
}
