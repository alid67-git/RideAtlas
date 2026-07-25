import 'package:gpx/gpx.dart' as gpxlib;
import 'package:xml/xml.dart';

import '../models/parsed_track.dart';
import '../models/track_point.dart';
import '../models/waypoint.dart';
import 'gpx_parser.dart';
import 'kml_parser.dart';

enum TrackFormat {
  gpx('gpx', 'GPX', 'application/gpx+xml'),
  kml('kml', 'KML', 'application/vnd.google-earth.kml+xml');

  const TrackFormat(this.extension, this.label, this.mimeType);

  final String extension;
  final String label;
  final String mimeType;
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
  };
}
