import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

import '../models/parsed_track.dart';
import '../models/track_point.dart';
import '../models/waypoint.dart';

/// Parses raw KML XML into track points and waypoints.
///
/// Supports the two common shapes GPS/mapping tools export: a plain
/// `<Placemark><LineString><coordinates>` path (no timestamps), and Google
/// Earth's `<gx:Track>` with paired `<when>`/`<gx:coord>` elements (which do
/// carry timestamps and are preferred when present). `<Placemark><Point>`
/// elements become waypoints. Namespace prefixes are ignored - elements are
/// matched by local name only, since KML files vary in how they declare the
/// `gx` namespace.
ParsedTrack parseKmlXml(String xmlText) {
  final doc = XmlDocument.parse(xmlText);
  final allElements = doc.descendants.whereType<XmlElement>();

  String? suggestedName;
  for (final el in allElements) {
    if (el.name.local != 'name') continue;
    final parent = el.parent;
    final parentLocal = parent is XmlElement ? parent.name.local : null;
    if (parentLocal != 'Document' &&
        parentLocal != 'kml' &&
        parentLocal != 'Folder') {
      continue;
    }
    final text = el.innerText.trim();
    if (text.isNotEmpty) {
      suggestedName = text;
      break;
    }
  }

  final points = <TrackPoint>[];

  var usedGxTrack = false;
  for (final trackEl in allElements.where((e) => e.name.local == 'Track')) {
    final children = trackEl.children.whereType<XmlElement>();
    final whens = children
        .where((e) => e.name.local == 'when')
        .map((e) => e.innerText.trim())
        .toList();
    final coords = children
        .where((e) => e.name.local == 'coord')
        .map((e) => e.innerText.trim())
        .toList();
    if (coords.isEmpty) continue;

    usedGxTrack = true;
    for (var i = 0; i < coords.length; i++) {
      final parts = coords[i].split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final lon = double.tryParse(parts[0]);
      final lat = double.tryParse(parts[1]);
      if (lon == null || lat == null) continue;
      final ele = parts.length > 2 ? double.tryParse(parts[2]) : null;
      final time = i < whens.length ? DateTime.tryParse(whens[i]) : null;
      points.add(
        TrackPoint(latLng: LatLng(lat, lon), elevation: ele, time: time),
      );
    }
  }

  if (!usedGxTrack) {
    for (final lineEl in allElements.where(
      (e) => e.name.local == 'LineString',
    )) {
      final coordEl = _child(lineEl, 'coordinates');
      if (coordEl == null) continue;
      for (final tuple in coordEl.innerText.trim().split(RegExp(r'\s+'))) {
        if (tuple.trim().isEmpty) continue;
        final parts = tuple.split(',');
        if (parts.length < 2) continue;
        final lon = double.tryParse(parts[0]);
        final lat = double.tryParse(parts[1]);
        if (lon == null || lat == null) continue;
        final ele = parts.length > 2 ? double.tryParse(parts[2]) : null;
        points.add(TrackPoint(latLng: LatLng(lat, lon), elevation: ele));
      }
    }
  }

  final waypoints = <Waypoint>[];
  for (final placemark in allElements.where(
    (e) => e.name.local == 'Placemark',
  )) {
    final pointEl = _child(placemark, 'Point');
    if (pointEl == null) continue;
    final coordEl = _child(pointEl, 'coordinates');
    if (coordEl == null) continue;

    final parts = coordEl.innerText.trim().split(',');
    if (parts.length < 2) continue;
    final lon = double.tryParse(parts[0]);
    final lat = double.tryParse(parts[1]);
    if (lon == null || lat == null) continue;

    waypoints.add(
      Waypoint(
        latLng: LatLng(lat, lon),
        name: _child(placemark, 'name')?.innerText.trim(),
        description: _child(placemark, 'description')?.innerText.trim(),
      ),
    );
  }

  return ParsedTrack(
    points: points,
    waypoints: waypoints,
    suggestedName: suggestedName,
  );
}

XmlElement? _child(XmlElement parent, String localName) {
  for (final c in parent.children.whereType<XmlElement>()) {
    if (c.name.local == localName) return c;
  }
  return null;
}
