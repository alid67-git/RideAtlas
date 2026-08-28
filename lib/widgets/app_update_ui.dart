import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/gen/app_localizations.dart';
import '../services/app_update_controller.dart';
import '../services/update_checker.dart';
import 'app_update_progress.dart';

/// Compact banner: version text + single "Güncelle" button, or inline
/// download progress while the APK streams in the background (MedyaAtlas-style).
class AppUpdateBanner extends StatelessWidget {
  const AppUpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AppUpdateController>();
    if (!ctrl.showBanner) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    if (ctrl.installing) {
      final progress = ctrl.downloadProgress;
      final received = progress?.$1 ?? 0;
      final total = progress?.$2 ?? ctrl.available?.sizeBytes ?? 0;
      return Material(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: AppUpdateProgressStrip(
            received: received,
            total: total,
            title: l10n.updateDownloadingTitle,
          ),
        ),
      );
    }

    final info = ctrl.available!;
    return Material(
      color: theme.colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.updateAvailableMessage(info.version),
                style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
              ),
            ),
            FilledButton(
              onPressed: () => installAppUpdate(context),
              child: Text(l10n.updateButtonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens a one-button "Güncelle" dialog when [ctrl.available] is set and not
/// yet dismissed. Returns whether the user tapped Update.
Future<bool> offerAppUpdateDialog(BuildContext context) async {
  final ctrl = context.read<AppUpdateController>();
  final info = ctrl.available;
  if (info == null || ctrl.dismissed || ctrl.installing) return false;

  final l10n = AppLocalizations.of(context)!;
  final accepted = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (context) => AlertDialog(
      title: Text(l10n.updateAvailableTitle),
      content: Text(l10n.updateAvailableMessage(info.version)),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.updateButtonLabel),
        ),
      ],
    ),
  );
  return accepted == true;
}

/// Downloads the APK in the background; progress appears in [AppUpdateBanner]
/// on home / record screens so the rider can keep using the app.
Future<void> installAppUpdate(BuildContext context) async {
  final ctrl = context.read<AppUpdateController>();
  final info = ctrl.available;
  if (info == null || ctrl.installing) return;

  ctrl.beginInstall();

  var success = false;
  try {
    await downloadAndInstallUpdate(
      info,
      onProgress: (received, total) {
        final known = total ?? (info.sizeBytes > 0 ? info.sizeBytes : 0);
        ctrl.reportDownloadProgress(received, known);
      },
    );
    success = true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.updateAvailableTitle,
          ),
        ),
      );
    }
    try {
      await launchUrl(
        Uri.parse(info.downloadUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  } finally {
    ctrl.endInstall(success: success);
  }
}
