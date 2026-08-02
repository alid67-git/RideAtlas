import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:latlong2/latlong.dart';

/// Reads the GPS coordinates embedded in a photo's EXIF metadata, if any.
/// Returns null for photos with no location tag (PNG, screenshots, GPS
/// turned off when the photo was taken, etc.) - the caller falls back to an
/// un-geotagged photo in that case.
Future<LatLng?> extractExifGps(Uint8List bytes) async {
  final tags = await readExifFromBytes(bytes);
  if (tags.isEmpty) return null;

  final latRef = tags['GPS GPSLatitudeRef']?.toString();
  final lngRef = tags['GPS GPSLongitudeRef']?.toString();
  var lat = _gpsValuesToDegrees(tags['GPS GPSLatitude']?.values);
  var lng = _gpsValuesToDegrees(tags['GPS GPSLongitude']?.values);
  if (latRef == null || lat == null || lngRef == null || lng == null) {
    return null;
  }

  if (latRef == 'S') lat = -lat;
  if (lngRef == 'W') lng = -lng;
  return LatLng(lat, lng);
}

double? _gpsValuesToDegrees(IfdValues? values) {
  if (values is! IfdRatios) return null;
  var sum = 0.0;
  var unit = 1.0;
  for (final ratio in values.ratios) {
    sum += ratio.toDouble() * unit;
    unit /= 60.0;
  }
  return sum;
}
