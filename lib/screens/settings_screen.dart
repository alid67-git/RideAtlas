import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../repositories/locale_controller.dart';
import '../repositories/satellite_visibility_controller.dart';
import '../repositories/stat_icon_settings_controller.dart';
import '../repositories/vehicle_icon_controller.dart';
import '../services/battery_optimization.dart';
import '../widgets/vehicle_marker.dart';
import 'about_screen.dart';
import 'help_screen.dart';
import 'language_picker.dart';
import 'stat_icon_settings_screen.dart';
import 'vehicle_icon_picker_screen.dart';

/// App-bar-style icon that opens [SettingsScreen]. Replaces the old
/// language-only icon: language is now one entry inside settings, alongside
/// help and about.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return IconButton(
      icon: const Icon(Icons.settings),
      tooltip: l10n.settingsTitle,
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = context.watch<LocaleController>().locale;
    final currentLanguageLabel = switch (locale?.languageCode) {
      'en' => l10n.languageEnglish,
      'de' => l10n.languageGerman,
      _ => l10n.languageTurkish,
    };
    final vehicleIcon = context.watch<VehicleIconController>().option;
    final satelliteController = context.watch<SatelliteVisibilityController>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(l10n.languagePickerTitle),
            subtitle: Text(currentLanguageLabel),
            onTap: () => showLanguagePicker(context),
          ),
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text(l10n.locationAlwaysAllowTitle),
              subtitle: Text(l10n.locationAlwaysAllowSubtitle),
              onTap: Geolocator.openAppSettings,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.battery_saver_outlined),
              title: Text(l10n.batteryOptimizationTitle),
              subtitle: Text(l10n.batteryOptimizationSubtitle),
              onTap: requestIgnoreBatteryOptimizations,
            ),
            const Divider(height: 1),
            SwitchListTile(
              secondary: const Icon(Icons.satellite_alt_outlined),
              title: Text(l10n.satelliteCountTitle),
              subtitle: Text(l10n.satelliteCountSubtitle),
              value: satelliteController.visible,
              onChanged: satelliteController.setVisible,
            ),
          ],
          const Divider(height: 1),
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
              MaterialPageRoute(builder: (_) => const VehicleIconPickerScreen()),
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
              MaterialPageRoute(builder: (_) => const StatIconSettingsScreen()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: Text(l10n.helpTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HelpScreen()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.aboutTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
