import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../repositories/stat_icon_settings_controller.dart';
import '../repositories/vehicle_icon_controller.dart';
import '../widgets/vehicle_marker.dart';
import 'live_stats_layout_screen.dart';
import 'stat_icon_settings_screen.dart';
import 'vehicle_icon_picker_screen.dart';

/// Settings > Arayüz: vehicle marker, stat icon look, live recording cards.
class InterfaceSettingsScreen extends StatelessWidget {
  const InterfaceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final vehicleIcon = context.watch<VehicleIconController>().option;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsInterfaceSection)),
      body: ListView(
        children: [
          ListTile(
            leading: SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: SizedBox(
                  width: vehicleMarkerSize(vehicleIcon),
                  height: vehicleMarkerSize(vehicleIcon),
                  child: buildVehicleMarker(vehicleIcon),
                ),
              ),
            ),
            title: Text(l10n.vehicleIconTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const VehicleIconPickerScreen(),
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              Icons.route,
              color: context.watch<StatIconSettingsController>().color,
            ),
            title: Text(l10n.statIconSettingsTitle),
            subtitle: Text(l10n.statIconSettingsSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const StatIconSettingsScreen(),
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.dashboard_customize_outlined),
            title: Text(l10n.liveStatsLayoutTitle),
            subtitle: Text(l10n.liveStatsLayoutSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const LiveStatsLayoutScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
