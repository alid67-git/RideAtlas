import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../build_info.dart';
import '../l10n/gen/app_localizations.dart';
import '../repositories/advanced_mode_controller.dart';
import '../repositories/daily_drive_backup_controller.dart';
import '../repositories/locale_controller.dart';
import '../repositories/satellite_visibility_controller.dart';
import '../services/app_update_controller.dart';
import '../services/backup_folder_bridge.dart';
import '../services/battery_optimization.dart';
import '../services/gps_recorder.dart';
import '../services/update_checker.dart';
import '../services/web_update_check.dart';
import '../widgets/app_update_ui.dart';
import 'about_screen.dart';
import 'help_screen.dart';
import 'interface_settings_screen.dart';
import 'language_picker.dart';
import 'route_list_screen.dart';

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
    final satelliteController = context.watch<SatelliteVisibilityController>();
    final advanced = context.watch<AdvancedModeController>();

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
            if (BackupFolderBridge.isSupported) ...[
              const Divider(height: 1),
              const _DailyDriveBackupSettings(),
            ],
          ],
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.list_alt_outlined),
            title: Text(l10n.routesDialogTitle),
            subtitle: Text(l10n.manageRoutesSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RouteListScreen()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text(l10n.settingsInterfaceSection),
            subtitle: Text(l10n.settingsInterfaceSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const InterfaceSettingsScreen(),
              ),
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.tune),
            title: Text(l10n.advancedModeTitle),
            subtitle: Text(l10n.advancedModeSubtitle),
            value: advanced.enabled,
            onChanged: advanced.setEnabled,
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
          const _CheckForUpdatesTile(),
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

/// Settings row: show the running build, probe for a newer one, and offer
/// install when available (Android APK / web service-worker banner).
class _CheckForUpdatesTile extends StatefulWidget {
  const _CheckForUpdatesTile();

  @override
  State<_CheckForUpdatesTile> createState() => _CheckForUpdatesTileState();
}

class _CheckForUpdatesTileState extends State<_CheckForUpdatesTile> {
  bool _webChecking = false;

  bool get _android => AppUpdateController.isSupported;
  bool get _web => kIsWeb;

  Future<void> _onTap() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    if (_android) {
      final ctrl = context.read<AppUpdateController>();
      if (ctrl.installing || ctrl.isChecking) return;
      if (ctrl.available != null && !ctrl.dismissed) {
        await installAppUpdate(context);
        return;
      }
      final status = await ctrl.checkNow();
      if (!mounted) return;
      switch (status) {
        case AndroidUpdateProbeStatus.upToDate:
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.updateUpToDateMessage)),
          );
        case AndroidUpdateProbeStatus.updateAvailable:
          final info = ctrl.available;
          if (info != null) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(l10n.updateAvailableMessage(info.version)),
                action: SnackBarAction(
                  label: l10n.updateButtonLabel,
                  onPressed: () {
                    if (context.mounted) installAppUpdate(context);
                  },
                ),
              ),
            );
          }
        case AndroidUpdateProbeStatus.failed:
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.updateCheckFailedMessage)),
          );
      }
      return;
    }

    if (_web) {
      if (_webChecking) return;
      setState(() => _webChecking = true);
      final result = await checkWebUpdate();
      if (!mounted) return;
      setState(() => _webChecking = false);
      final message = switch (result) {
        'available' => l10n.updateWebAvailableMessage,
        'upToDate' => l10n.updateUpToDateMessage,
        'unsupported' => l10n.updateCheckFailedMessage,
        _ => l10n.updateCheckFailedMessage,
      };
      messenger.showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    messenger.showSnackBar(
      SnackBar(content: Text(l10n.updateCheckUnsupportedMessage)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    if (_android) {
      final ctrl = context.watch<AppUpdateController>();
      final checking = ctrl.isChecking;
      final installing = ctrl.installing;
      final info = ctrl.available;
      final offer = info != null && !ctrl.dismissed;

      String subtitle;
      if (installing) {
        subtitle = l10n.updateDownloadingTitle;
      } else if (offer) {
        subtitle = l10n.updateAvailableMessage(info.version);
      } else {
        subtitle = l10n.appRunningVersion(kAppBuildLabel);
      }

      return ListTile(
        leading: const Icon(Icons.system_update_alt),
        title: Text(l10n.checkForUpdatesTitle),
        subtitle: Text(subtitle),
        trailing: checking || installing
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : offer
            ? FilledButton(
                onPressed: () => installAppUpdate(context),
                child: Text(l10n.updateButtonLabel),
              )
            : Icon(
                Icons.refresh,
                color: theme.colorScheme.onSurfaceVariant,
              ),
        onTap: checking || installing ? null : _onTap,
      );
    }

    return ListTile(
      leading: const Icon(Icons.system_update_alt),
      title: Text(l10n.checkForUpdatesTitle),
      subtitle: Text(l10n.appRunningVersion(kAppBuildLabel)),
      trailing: _webChecking
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              Icons.refresh,
              color: theme.colorScheme.onSurfaceVariant,
            ),
      onTap: _webChecking ? null : _onTap,
    );
  }
}

/// Android-only: enable daily Drive/SAF backup and pick the destination
/// folder (Google Drive is offered by the system folder picker).
class _DailyDriveBackupSettings extends StatelessWidget {
  const _DailyDriveBackupSettings();

  Future<void> _pickFolderAndCatchUp(BuildContext context) async {
    final backup = context.read<DailyDriveBackupController>();
    final ok = await backup.pickFolder();
    if (!ok || !context.mounted) return;
    // Re-selecting the Drive folder is often how riders recover after
    // permission loss — write every missing day from the live session now.
    final recorder = context.read<GpsRecorder>();
    if (recorder.isIdle || recorder.points.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final result = await backup.backupDaysPresent(
      points: List.of(recorder.points),
      includeToday: true,
      rewriteExisting: true,
    );
    if (!context.mounted) return;
    if (!result.hadWork) return;
    final message = result.failed > 0
        ? l10n.dailyDriveBackupCatchUpFailed(result.written, result.failed)
        : l10n.dailyDriveBackupCatchUpDone(result.written);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final backup = context.watch<DailyDriveBackupController>();
    final folderLabel = backup.folderName;
    final errorKey = backup.lastError;
    final subtitle = !backup.enabled
        ? l10n.dailyDriveBackupOffSubtitle
        : errorKey != null
        ? l10n.dailyDriveBackupErrorSubtitle(errorKey)
        : folderLabel == null || folderLabel.isEmpty
        ? l10n.dailyDriveBackupPickFolderSubtitle
        : l10n.dailyDriveBackupFolderSubtitle(folderLabel);

    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.cloud_upload_outlined),
          title: Text(l10n.dailyDriveBackupTitle),
          subtitle: Text(subtitle),
          value: backup.enabled,
          onChanged: backup.isLoading
              ? null
              : (value) async {
                  await backup.setEnabled(value);
                  if (value &&
                      (backup.folderUri == null || backup.folderUri!.isEmpty) &&
                      context.mounted) {
                    await _pickFolderAndCatchUp(context);
                    if (backup.folderUri == null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l10n.dailyDriveBackupPickFolderSubtitle),
                        ),
                      );
                    }
                  }
                },
        ),
        if (backup.enabled) ...[
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(l10n.dailyDriveBackupPickFolderTitle),
            subtitle: Text(
              folderLabel == null || folderLabel.isEmpty
                  ? l10n.dailyDriveBackupPickFolderSubtitle
                  : folderLabel,
            ),
            trailing: backup.isBusy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: backup.isBusy ? null : () => _pickFolderAndCatchUp(context),
          ),
        ],
      ],
    );
  }
}
