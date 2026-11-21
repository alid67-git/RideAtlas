import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/track_point.dart';
import '../models/waypoint.dart';
import '../widgets/busy_progress_dialog.dart';
import 'backup_folder_bridge.dart';
import 'day_export.dart';
import 'track_export_actions.dart';
import 'track_io.dart';

/// Asks GPX / KML / KMZ. Returns null if cancelled.
Future<TrackFormat?> pickExportFormat(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  return showDialog<TrackFormat>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(l10n.exportFormatQuestion),
      children: [
        for (final f in TrackFormat.values)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, f),
            child: Text(f.label),
          ),
      ],
    ),
  );
}

/// Asks folder vs share sheet. Returns null if cancelled.
Future<DayExportDestination?> pickExportDestination(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  final folderOk = BackupFolderBridge.isSupported;
  return showDialog<DayExportDestination>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(l10n.dayExportDestinationTitle),
      children: [
        if (folderOk)
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(context, DayExportDestination.folder),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.dayExportDestinationFolder),
              subtitle: Text(l10n.dayExportDestinationFolderHint),
            ),
          ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, DayExportDestination.share),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.dayExportDestinationShare),
            subtitle: Text(l10n.dayExportDestinationShareHint),
          ),
        ),
      ],
    ),
  );
}

/// Builds files then writes/shares with progress dialogs.
/// Returns true when something was delivered.
Future<bool> runPreparedDayExport({
  required BuildContext context,
  required DayExportPlan plan,
  required String routeName,
  required List<TrackPoint> points,
  required List<Waypoint> waypoints,
  required TrackFormat format,
}) async {
  final l10n = AppLocalizations.of(context)!;

  late final List<PreparedExportFile> files;
  try {
    files = await runBusyProgress(
      context: context,
      message: l10n.busyPreparingExport,
      action: (_) async {
        await Future<void>.delayed(Duration.zero);
        return preparePlanExportFiles(
          plan: plan,
          routeName: routeName,
          points: points,
          waypoints: waypoints,
          format: format,
        );
      },
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.dayExportFailed)),
      );
    }
    return false;
  }
  if (files.isEmpty || !context.mounted) return false;

  String? result;
  if (plan.destination == DayExportDestination.folder) {
    if (!BackupFolderBridge.isSupported) return false;
    final picked = await BackupFolderBridge.pickFolder();
    if (picked == null || !context.mounted) return false;
    try {
      result = await runBusyProgress(
        context: context,
        message: l10n.busyWritingExportProgress(1, files.length),
        action: (setMessage) async {
          for (var i = 0; i < files.length; i++) {
            setMessage(l10n.busyWritingExportProgress(i + 1, files.length));
            final ok = await BackupFolderBridge.writeFile(
              uri: picked.uri,
              fileName: files[i].fileName,
              bytes: files[i].export.bytes,
            );
            if (!ok) return null;
          }
          return picked.name;
        },
      );
    } catch (_) {
      result = null;
    }
  } else {
    try {
      result = await runBusyProgress(
        context: context,
        message: l10n.busyPreparingExport,
        action: (_) async {
          await shareExportFiles(files, subject: routeName);
          return 'share';
        },
      );
    } catch (_) {
      result = null;
    }
  }

  if (!context.mounted) return false;
  if (result == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.dayExportFailed)),
    );
    return false;
  }
  if (plan.destination == DayExportDestination.folder) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.dayExportSavedToFolder(result))),
    );
  }
  return true;
}

/// One calendar day → destination + format + deliver (same order as the
/// multi-day export dialog: “Nereye?” then GPX/KML/KMZ). File name is
/// `RideAtlas_yyyy-MM-dd` — no second rename prompt.
Future<bool> exportSingleCalendarDay({
  required BuildContext context,
  required String routeName,
  required List<TrackPoint> points,
  required List<Waypoint> waypoints,
  required DateTime day,
}) async {
  final destination = await pickExportDestination(context);
  if (destination == null || !context.mounted) return false;
  final format = await pickExportFormat(context);
  if (format == null || !context.mounted) return false;
  return runPreparedDayExport(
    context: context,
    plan: DayExportPlan(
      scope: DayExportScope.selectedDays,
      destination: destination,
      selectedDays: [DateTime(day.year, day.month, day.day)],
    ),
    routeName: routeName,
    points: points,
    waypoints: waypoints,
    format: format,
  );
}
