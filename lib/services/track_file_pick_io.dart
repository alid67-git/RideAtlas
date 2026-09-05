import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Native (Android/iOS/desktop): opens the OS file picker for GPX/KML/KMZ
/// import (one file, or several at once with [allowMultiple]).
///
/// Filtering by extension differs by platform on purpose: Android's
/// MimeTypeMap often has no entry for "gpx", and the system document
/// picker then hides those files entirely instead of just failing to
/// match them - so on Android we request [FileType.any] and validate the
/// extension ourselves afterwards (see `isSupportedTrackFileName`).
/// Elsewhere, restricting to [FileType.custom] with our three extensions
/// avoids iOS additionally offering "Photo Library"/"Take Photo or
/// Video" alongside "Choose File" - that extra menu appears whenever the
/// allowed types are broad enough to include images, which
/// [FileType.any] is.
Future<FilePickerResult?> pickTrackFiles({bool allowMultiple = false}) {
  final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  return FilePicker.pickFiles(
    type: isAndroid ? FileType.any : FileType.custom,
    allowedExtensions: isAndroid ? null : const ['gpx', 'kml', 'kmz'],
    withData: true,
    allowMultiple: allowMultiple,
  );
}
