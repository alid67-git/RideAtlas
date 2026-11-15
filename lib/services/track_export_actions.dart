import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/track_point.dart';
import '../models/waypoint.dart';
import 'backup_folder_bridge.dart';
import 'daily_backup.dart';
import 'day_export.dart';
import 'track_io.dart';

/// One named file ready to share or write to a folder.
class PreparedExportFile {
  const PreparedExportFile({
    required this.baseName,
    required this.export,
  });

  final String baseName;
  final TrackExport export;

  String get fileName => '$baseName.${export.extension}';
}

/// Shares [files] via the system share sheet. On non-web, writes temp files
/// so Android shows the chosen names.
Future<void> shareExportFiles(
  List<PreparedExportFile> files, {
  String? subject,
}) async {
  if (files.isEmpty) return;
  final xFiles = <XFile>[];
  if (kIsWeb) {
    for (final f in files) {
      xFiles.add(
        XFile.fromData(
          f.export.bytes,
          name: f.fileName,
          mimeType: f.export.mimeType,
        ),
      );
    }
  } else {
    final tempDir = await getTemporaryDirectory();
    for (final f in files) {
      final safe = f.baseName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final path = '${tempDir.path}/$safe.${f.export.extension}';
      final file = File(path);
      await file.writeAsBytes(f.export.bytes);
      xFiles.add(XFile(path, mimeType: f.export.mimeType));
    }
  }
  await SharePlus.instance.share(
    ShareParams(
      files: xFiles,
      subject: subject ?? files.first.baseName,
    ),
  );
}

/// Writes every file into [folderUri] (existing persistable SAF tree).
/// Returns [folderName] on success, null if unsupported / failed.
Future<String?> writeExportFilesToFolder({
  required List<PreparedExportFile> files,
  required String folderUri,
  String? folderName,
}) async {
  if (!BackupFolderBridge.isSupported || files.isEmpty) return null;
  if (folderUri.isEmpty) return null;
  for (final f in files) {
    final ok = await BackupFolderBridge.writeFile(
      uri: folderUri,
      fileName: f.fileName,
      bytes: f.export.bytes,
    );
    if (!ok) return null;
  }
  return folderName ?? 'Drive';
}

/// Opens the SAF folder picker and writes every file. Returns the folder
/// display name on success, null if cancelled or unsupported / failed.
Future<String?> writeExportFilesToPickedFolder(
  List<PreparedExportFile> files,
) async {
  if (!BackupFolderBridge.isSupported || files.isEmpty) return null;
  final picked = await BackupFolderBridge.pickFolder();
  if (picked == null) return null;
  return writeExportFilesToFolder(
    files: files,
    folderUri: picked.uri,
    folderName: picked.name,
  );
}

/// Delivers [files] according to [destination].
/// Returns `share`, the folder display name, or null if cancelled/failed.
///
/// When [destination] is [DayExportDestination.folder] and
/// [existingFolderUri] is set (e.g. Ayarlar → Günlük Drive yedeği), writes
/// there without opening another picker so all days land in one shot.
Future<String?> deliverExportFiles({
  required List<PreparedExportFile> files,
  required DayExportDestination destination,
  String? subject,
  String? existingFolderUri,
  String? existingFolderName,
}) async {
  if (files.isEmpty) return null;
  switch (destination) {
    case DayExportDestination.share:
      await shareExportFiles(files, subject: subject);
      return 'share';
    case DayExportDestination.folder:
      final uri = existingFolderUri;
      if (uri != null && uri.isNotEmpty) {
        return writeExportFilesToFolder(
          files: files,
          folderUri: uri,
          folderName: existingFolderName,
        );
      }
      return writeExportFilesToPickedFolder(files);
  }
}

/// Builds the file list for a multi-day [plan] (or a single full-route file).
List<PreparedExportFile> preparePlanExportFiles({
  required DayExportPlan plan,
  required String routeName,
  required List<TrackPoint> points,
  required List<Waypoint> waypoints,
  required TrackFormat format,
}) {
  if (plan.scope == DayExportScope.fullRoute) {
    final safe = routeName.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final base = safe.isEmpty ? 'RideAtlas' : safe;
    return [
      PreparedExportFile(
        baseName: base,
        export: buildTrackExport(
          name: routeName,
          points: points,
          waypoints: waypoints,
          format: format,
        ),
      ),
    ];
  }

  final out = <PreparedExportFile>[];
  for (final day in plan.selectedDays) {
    final export = buildDayTrackExport(
      allPoints: points,
      waypoints: waypoints,
      day: day,
      format: format,
      nameOverride: '${routeName.trim()} ${dayBackupKey(day)}',
    );
    if (export == null) continue;
    out.add(
      PreparedExportFile(
        baseName: dayExportBaseName(day, routeName: routeName),
        export: export,
      ),
    );
  }
  return out;
}
