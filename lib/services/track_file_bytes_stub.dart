import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Stub: no filesystem; only inlined picker bytes.
Future<Uint8List?> readPickedTrackBytes(PlatformFile file) async {
  final bytes = file.bytes;
  if (bytes == null || bytes.isEmpty) return null;
  return bytes;
}
