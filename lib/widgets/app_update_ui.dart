import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/gen/app_localizations.dart';
import '../services/app_update_controller.dart';
import '../services/update_checker.dart';
import 'app_update_progress.dart';

/// Space to lift map FABs so they sit above the bottom update banner.
const double kAppUpdateBannerReserve = 80;

/// Compact bottom banner: version text + "Güncelle" + optional dismiss, or
/// inline download progress while the APK streams (same language as the
/// web #update-banner).
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
      return Semantics(
        container: true,
        liveRegion: true,
        child: Material(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: AppUpdateProgressStrip(
              received: received,
              total: total,
              title: l10n.updateDownloadingTitle,
            ),
          ),
        ),
      );
    }

    final info = ctrl.available!;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Material(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
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
              IconButton(
                tooltip: l10n.close,
                onPressed: ctrl.dismiss,
                icon: Icon(
                  Icons.close,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
