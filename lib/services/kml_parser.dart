import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

import '../models/parsed_track.dart';
import '../models/track_point.dart';
import '../models/waypoint.dart';

/// Parses raw KML XML into track points and waypoints.
///
/// Handles nested Folder/Placemark/MultiGeometry trees, multiple LineStrings,
/// gx:Track / MultiTrack (when/coord pairs in order), LinearRing boundaries,
/// and rich exports from Google Earth, Garmin, etc.
ParsedTrack parseKmlXml(String xmlText) {
  final doc = XmlDocument.parse(xmlText);
  final root = doc.rootElement;

  final suggestedName = _findDocumentName(root);
  final points = <TrackPoint>[];
  _collectGeometryPoints(root, points);

  final waypoints = <Waypoint>[];
  for (final placemark in root.descendants.whereType<XmlElement>()) {
    if (placemark.name.local != 'Placemark') continue;
    if (_placemarkHasLineGeometry(placemark)) continue;
    final pointEl = _firstDescendant(placemark, 'Point');
    if (pointEl == null) continue;
    final coordEl = _firstDescendant(pointEl, 'coordinates');
    if (coordEl == null) continue;
    final ll = _parseLonLat(coordEl.innerText);
    if (ll == null) continue;
    waypoints.add(
      Waypoint(
        latLng: ll,
        name: _firstDescendant(placemark, 'name')?.innerText.trim(),
        description: _firstDescendant(placemark, 'description')?.innerText.trim(),
      ),
    );
  }

  return ParsedTrack(
    points: points,
    waypoints: waypoints,
    suggestedName: suggestedName,
  );
}

String? _findDocumentName(XmlElement root) {
  for (final el in root.descendants.whereType<XmlElement>()) {
    if (el.name.local != 'name') continue;
    final parent = el.parent;
    if (parent is! XmlElement) continue;
    final p = parent.name.local;
    if (p == 'Document' || p == 'kml' || p == 'Folder') {
      final text = el.innerText.trim();
      if (text.isNotEmpty) return text;
    }
  }
  return null;
}

void _collectGeometryPoints(XmlElement node, List<TrackPoint> out) {
  for (final child in node.children.whereType<XmlElement>()) {
    switch (child.name.local) {
      case 'Track':
        _parseGxTrack(child, out);
      case 'MultiTrack':
        for (final track in child.children.whereType<XmlElement>()) {
          if (track.name.local == 'Track') {
            _parseGxTrack(track, out);
          }
        }
      case 'LineString':
        _parseCoordinateElement(child, out);
      case 'LinearRing':
        _parseCoordinateElement(child, out);
      default:
        _collectGeometryPoints(child, out);
    }
  }
}

void _parseGxTrack(XmlElement trackEl, List<TrackPoint> out) {
  DateTime? pendingWhen;
  for (final child in trackEl.children.whereType<XmlElement>()) {
    switch (child.name.local) {
      case 'when':
        pendingWhen = DateTime.tryParse(child.innerText.trim());
      case 'coord':
        final parts = child.innerText.trim().split(RegExp(r'\s+'));
        if (parts.length < 2) continue;
        final lon = double.tryParse(parts[0]);
        final lat = double.tryParse(parts[1]);
        if (lon == null || lat == null) continue;
        final ele = parts.length > 2 ? double.tryParse(parts[2]) : null;
        out.add(
          TrackPoint(
            latLng: LatLng(lat, lon),
            elevation: ele,
            time: pendingWhen,
          ),
        );
        pendingWhen = null;
      default:
        break;
    }
  }
}

void _parseCoordinateElement(XmlElement geometryEl, List<TrackPoint> out) {
  final coordEl = _firstDescendant(geometryEl, 'coordinates');
  if (coordEl == null) return;
  for (final ll in _parseCoordinateTuples(coordEl.innerText)) {
    out.add(TrackPoint(latLng: ll));
  }
}

/// KML coordinate text: tuples of lon,lat[,alt] separated by whitespace.
Iterable<LatLng> _parseCoordinateTuples(String raw) {
  final tuples = <LatLng>[];
  for (final token in raw.trim().split(RegExp(r'\s+'))) {
    if (token.isEmpty) continue;
    final ll = _parseLonLat(token);
    if (ll != null) tuples.add(ll);
  }
  return tuples;
}

LatLng? _parseLonLat(String tuple) {
  final parts = tuple.split(',');
  if (parts.length < 2) return null;
  final lon = double.tryParse(parts[0].trim());
  final lat = double.tryParse(parts[1].trim());
  if (lon == null || lat == null) return null;
  return LatLng(lat, lon);
}

bool _placemarkHasLineGeometry(XmlElement placemark) {
  for (final el in placemark.descendants.whereType<XmlElement>()) {
    if (el == placemark) continue;
    final n = el.name.local;
    if (n == 'LineString' || n == 'LinearRing' || n == 'Track') {
      return true;
    }
  }
  return false;
}

XmlElement? _firstDescendant(XmlElement root, String localName) {
  if (root.name.local == localName) return root;
  for (final el in root.descendants.whereType<XmlElement>()) {
    if (el.name.local == localName) return el;
  }
  return null;
}
