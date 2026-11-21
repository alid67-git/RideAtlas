import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_update_controller.dart';
import '../services/update_checker.dart';
import 'app_update_progress.dart';

/// Compact banner: version + "Güncelle", or download progress while installing.
class AppUpdateBanner extends StatelessWidget {
  const AppUpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AppUpdateController>();
    if (!ctrl.showBanner) return const SizedBox.shrink();
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
            title: 'Güncelleme indiriliyor',
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
                'Yeni sürüm: ${info.version}',
                style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
              ),
            ),
            FilledButton(
              onPressed: () => installAppUpdate(context),
              child: const Text('Güncelle'),
            ),
          ],
        ),
      ),
    );
  }
}

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
        const SnackBar(
          content: Text('Kurulum açılamadı; tarayıcıdan indirme deneniyor.'),
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
