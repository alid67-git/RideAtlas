import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Web: picker / custom input already inlines bytes (no usable path).
Future<Uint8List?> readPickedTrackBytes(PlatformFile file) async {
  final bytes = file.bytes;
  if (bytes == null || bytes.isEmpty) return null;
  return bytes;
}
