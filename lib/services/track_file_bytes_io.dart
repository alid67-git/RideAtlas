import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Reads bytes for a picked track file on Android/iOS/desktop.
///
/// `file_picker` with `withData: true` still often returns `bytes: null` and
/// a usable cache [PlatformFile.path] (OOM on Android, failed NSData read on
/// iOS). Import callers that only check [PlatformFile.bytes] then report
/// "file not readable" and never save the GPX — the iPhone / flaky-Android
/// import bug. Fall back to path, then CrossFile (`xFile`).
Future<Uint8List?> readPickedTrackBytes(PlatformFile file) async {
  final inline = file.bytes;
  if (inline != null && inline.isNotEmpty) return inline;

  final path = file.path;
  if (path != null && path.isNotEmpty) {
    try {
      final bytes = await File(path).readAsBytes();
      if (bytes.isNotEmpty) return bytes;
    } catch (_) {
      // Try xFile below.
    }
  }

  try {
    final bytes = await file.xFile.readAsBytes();
    if (bytes.isNotEmpty) return bytes;
  } catch (_) {}

  return null;
}
