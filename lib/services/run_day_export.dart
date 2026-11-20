import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/track_point.dart';
import '../models/waypoint.dart';
import '../repositories/daily_drive_backup_controller.dart';
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

/// Runs format → destination → write/share for [plan]. Shows snackbars.
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
  final files = preparePlanExportFiles(
    plan: plan,
    routeName: routeName,
    points: points,
    waypoints: waypoints,
    format: format,
  );
  if (files.isEmpty || !context.mounted) return false;

  final backup = context.read<DailyDriveBackupController>();
  final result = await deliverExportFiles(
    files: files,
    destination: plan.destination,
    subject: routeName,
    existingFolderUri: backup.isConfigured ? backup.folderUri : null,
    existingFolderName: backup.isConfigured ? backup.folderName : null,
  );
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
