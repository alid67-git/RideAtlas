import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:gpx/gpx.dart' as gpxlib;
import 'package:xml/xml.dart';

import '../models/parsed_track.dart';
import '../models/track_point.dart';
import '../models/waypoint.dart';
import 'gpx_parser.dart';
import 'kml_parser.dart';

enum TrackFormat {
  gpx('gpx', 'GPX', 'application/gpx+xml'),
  kml('kml', 'KML', 'application/vnd.google-earth.kml+xml'),
  kmz('kmz', 'KMZ', 'application/vnd.google-earth.kmz');

  const TrackFormat(this.extension, this.label, this.mimeType);

  final String extension;
  final String label;
  final String mimeType;
}

/// File bytes ready for sharing (GPX/KML text or KMZ zip).
class TrackExport {
  const TrackExport({
    required this.bytes,
    required this.extension,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String extension;
  final String mimeType;
}

/// Decodes GPX/KML text or extracts KML from a KMZ zip archive.
String decodeTrackBytes(Uint8List bytes, {String? fileName}) {
  if (_isKmzArchive(bytes, fileName)) {
    return _extractKmlFromKmz(bytes);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

bool _isKmzArchive(Uint8List bytes, String? fileName) {
  if (fileName != null && fileName.toLowerCase().endsWith('.kmz')) {
    return true;
  }
  if (bytes.length < 2 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
    return false;
  }
  // Plain XML files are never KMZ even if misnamed.
  final head = utf8
      .decode(bytes.take(64).toList(), allowMalformed: true)
      .trimLeft();
  return !head.startsWith('<?xml') && !head.startsWith('<');
}

String _extractKmlFromKmz(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  ArchiveFile? docKml;
  ArchiveFile? anyKml;

  for (final file in archive) {
    if (!file.isFile) continue;
    final name = file.name.toLowerCase();
    if (!name.endsWith('.kml')) continue;
    anyKml ??= file;
    if (name.endsWith('doc.kml') || name == 'doc.kml') {
      docKml = file;
      break;
    }
  }

  final chosen = docKml ?? anyKml;
  if (chosen == null) {
    throw const FormatException('KMZ arşivinde KML dosyası bulunamadı.');
  }

  final content = chosen.content;
  return utf8.decode(content, allowMalformed: true);
}

Uint8List encodeKmz(String kmlXml) {
  final encoded = utf8.encode(kmlXml);
  final archive = Archive()
    ..addFile(ArchiveFile('doc.kml', encoded.length, encoded));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// Parses a track file of either format, detected by sniffing the XML root
/// element (`<gpx>` vs `<kml>`) so callers don't need to know or store which
/// format a given route was originally imported as.
ParsedTrack parseTrackXml(String xmlText) {
  final rootLocal = XmlDocument.parse(
    xmlText,
  ).rootElement.name.local.toLowerCase();
  return rootLocal == 'kml' ? parseKmlXml(xmlText) : parseGpxXml(xmlText);
}

/// Isolate-friendly: parse + drop GPS jump/glitch points in one shot so the
/// UI thread can show the map immediately and only animate the cleaned line.
ParsedTrack parseAndFilterTrackXml(String xmlText) {
  final parsed = parseTrackXml(xmlText);
  return ParsedTrack(
    points: filterImplausiblePoints(parsed.points),
    waypoints: parsed.waypoints,
    suggestedName: parsed.suggestedName,
  );
}

/// Serializes a track's points/waypoints/name into GPX or KML text, for
/// export/sharing. Regenerated fresh each time from the in-memory track
/// rather than round-tripping the original file, so either format is always
/// available regardless of what the route was imported as.
String exportTrack({
  required String name,
  required List<TrackPoint> points,
  required List<Waypoint> waypoints,
  required TrackFormat format,
}) {
  if (format == TrackFormat.kmz) {
    throw ArgumentError('Use buildTrackExport for KMZ.');
  }

  final gpx = gpxlib.Gpx()
    ..creator = 'RideAtlas'
    ..metadata = gpxlib.Metadata(name: name)
    ..wpts = [
      for (final w in waypoints)
        gpxlib.Wpt(
          lat: w.latLng.latitude,
          lon: w.latLng.longitude,
          name: w.name,
          desc: w.description,
        ),
    ]
    ..trks = [
      gpxlib.Trk(
        name: name,
        trksegs: [
          gpxlib.Trkseg(
            trkpts: [
              for (final p in points)
                gpxlib.Wpt(
                  lat: p.latLng.latitude,
                  lon: p.latLng.longitude,
                  ele: p.elevation,
                  time: p.time,
                ),
            ],
          ),
        ],
      ),
    ];

  return switch (format) {
    TrackFormat.gpx => gpxlib.GpxWriter().asString(gpx, pretty: true),
    TrackFormat.kml => gpxlib.KmlWriter().asString(gpx, pretty: true),
    TrackFormat.kmz => throw ArgumentError('Use buildTrackExport for KMZ.'),
  };
}

TrackExport buildTrackExport({
  required String name,
  required List<TrackPoint> points,
  required List<Waypoint> waypoints,
  required TrackFormat format,
}) {
  if (format == TrackFormat.kmz) {
    final kml = exportTrack(
      name: name,
      points: points,
      waypoints: waypoints,
      format: TrackFormat.kml,
    );
    return TrackExport(
      bytes: encodeKmz(kml),
      extension: format.extension,
      mimeType: format.mimeType,
    );
  }

  final text = exportTrack(
    name: name,
    points: points,
    waypoints: waypoints,
    format: format,
  );
  return TrackExport(
    bytes: Uint8List.fromList(utf8.encode(text)),
    extension: format.extension,
    mimeType: format.mimeType,
  );
}

final _trackExtensionPattern = RegExp(
  r'\.(gpx|kml|kmz)$',
  caseSensitive: false,
);

/// Strips common track file extensions from an imported file name.
String stripTrackExtension(String fileName) {
  return fileName.replaceAll(_trackExtensionPattern, '');
}

/// True when [fileName] ends in a track extension we can import. Used to
/// validate a file picked with an unfiltered picker (see [decodeTrackBytes]
/// callers) - filtering by extension *at the OS picker* is unreliable on
/// Android, where a device's MimeTypeMap often has no entry for "gpx" and
/// the document picker then hides those files entirely instead of just
/// failing to match them.
bool isSupportedTrackFileName(String fileName) =>
    _trackExtensionPattern.hasMatch(fileName);

/// Trims stray trailing separators (underscores, dashes, whitespace) left
/// over from a source filename, e.g. "Kapadokya_Turu_" -> "Kapadokya_Turu".
String cleanRouteName(String name) {
  return name.trim().replaceAll(RegExp(r'[\s_\-]+$'), '');
}
