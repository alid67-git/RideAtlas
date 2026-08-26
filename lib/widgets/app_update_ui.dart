import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/gen/app_localizations.dart';
import '../services/app_update_controller.dart';
import '../services/update_checker.dart';

/// Compact banner: version text + single "Güncelle" button.
class AppUpdateBanner extends StatelessWidget {
  const AppUpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AppUpdateController>();
    if (!ctrl.showBanner) return const SizedBox.shrink();
    final info = ctrl.available!;
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

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

/// Streams the APK with a percent progress dialog, then opens the installer.
Future<void> installAppUpdate(BuildContext context) async {
  final ctrl = context.read<AppUpdateController>();
  final info = ctrl.available;
  if (info == null || ctrl.installing) return;

  // Capture the root navigator before beginInstall(): that hides the banner
  // and can deactivate the calling widget's Element (e.g. AppUpdateBanner).
  final nav = Navigator.of(context, rootNavigator: true);
  final l10n = AppLocalizations.of(context)!;
  ctrl.beginInstall();

  // Prefer the GitHub asset size: CDN downloads often omit Content-Length
  // (chunked), which left the UI stuck on "…" with an indeterminate bar.
  final progress = ValueNotifier<(int received, int total)>((
    0,
    info.sizeBytes > 0 ? info.sizeBytes : 0,
  ));

  showDialog<void>(
    context: nav.context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(l10n.updateDownloadingTitle),
        content: ValueListenableBuilder<(int, int)>(
          valueListenable: progress,
          builder: (context, value, _) {
            final received = value.$1;
            final total = value.$2;
            final hasTotal = total > 0;
            final fraction = hasTotal
                ? (received / total).clamp(0.0, 1.0)
                : null;
            final percentLabel = hasTotal
                ? '%${(fraction! * 100).round()}'
                : '${(received / (1024 * 1024)).toStringAsFixed(1)} MB';
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(value: fraction),
                const SizedBox(height: 12),
                Text(
                  l10n.updateDownloadProgress(percentLabel),
                  textAlign: TextAlign.center,
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  var success = false;
  try {
    await downloadAndInstallUpdate(
      info,
      onProgress: (received, total) {
        final known = total ?? (info.sizeBytes > 0 ? info.sizeBytes : 0);
        final prev = progress.value;
        // Skip tiny updates so the UI isn't flooded every TCP chunk.
        if (known > 0) {
          final prevPct = prev.$2 > 0 ? (prev.$1 * 100 ~/ prev.$2) : -1;
          final nextPct = received * 100 ~/ known;
          if (nextPct == prevPct && received < known) return;
        } else if (received - prev.$1 < 256 * 1024) {
          return;
        }
        progress.value = (received, known);
      },
    );
    success = true;
  } catch (_) {
    try {
      await launchUrl(
        Uri.parse(info.downloadUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  } finally {
    progress.dispose();
    if (nav.canPop()) nav.pop();
    ctrl.endInstall(success: success);
  }
}
