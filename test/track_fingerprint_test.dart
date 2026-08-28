import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rideatlas/models/track_point.dart';
import 'package:rideatlas/services/gpx_parser.dart';
import 'package:rideatlas/services/track_io.dart';

void main() {
  group('trackFingerprint', () {
    TrackPoint pt(double lat, double lon, {DateTime? time}) =>
        TrackPoint(latLng: LatLng(lat, lon), time: time);

    test('identical point sequences match', () {
      final t0 = DateTime.utc(2026, 8, 27, 10);
      final a = [
        pt(41.0, 29.0, time: t0),
        pt(41.01, 29.01, time: t0.add(const Duration(minutes: 1))),
      ];
      final b = [
        pt(41.0, 29.0, time: t0),
        pt(41.01, 29.01, time: t0.add(const Duration(minutes: 1))),
      ];
      expect(trackFingerprint(a), trackFingerprint(b));
    });

    test('different paths do not match', () {
      final a = [pt(41.0, 29.0), pt(41.01, 29.01)];
      final b = [pt(41.0, 29.0), pt(41.02, 29.02)];
      expect(trackFingerprint(a), isNot(trackFingerprint(b)));
    });

    test('same track re-exported as GPX still matches after parse', () {
      final t0 = DateTime.utc(2026, 8, 1, 8);
      final points = [
        for (var i = 0; i < 20; i++)
          pt(
            41.0 + i * 0.001,
            29.0 + i * 0.001,
            time: t0.add(Duration(minutes: i)),
          ),
      ];
      final original = trackFingerprint(points);
      final gpx = exportTrack(
        name: 'Test',
        points: points,
        waypoints: const [],
        format: TrackFormat.gpx,
      );
      final parsed = parseTrackXml(gpx);
      expect(trackFingerprint(parsed.points), original);
    });

    test('file name / suggested name does not affect fingerprint', () {
      final points = [pt(40.0, 30.0), pt(40.1, 30.1)];
      final gpx = exportTrack(
        name: 'Whatever',
        points: points,
        waypoints: const [],
        format: TrackFormat.gpx,
      );
      final a = parseTrackXml(gpx);
      final b = parseTrackXml(gpx.replaceAll('Whatever', 'Other name'));
      expect(trackFingerprint(a.points), trackFingerprint(b.points));
    });
  });

  group('recordedAt from GPX', () {
    test('buildRouteMetadata uses first GPS time for sorting key', () {
      final start = DateTime.utc(2026, 8, 20, 6, 30);
      final points = [
        TrackPoint(latLng: const LatLng(41, 29), time: start),
        TrackPoint(
          latLng: const LatLng(41.01, 29.01),
          time: start.add(const Duration(hours: 2)),
        ),
      ];
      final gpx = exportTrack(
        name: 'Ride',
        points: points,
        waypoints: const [],
        format: TrackFormat.gpx,
      );
      final parsed = parseTrackXml(gpx);
      final meta = buildRouteMetadata(
        id: 'x',
        name: 'Ride',
        importedAt: DateTime.utc(2026, 8, 28),
        parsed: parsed,
      );
      expect(meta.recordedAt.toUtc(), start);
      expect(meta.trackFingerprint, isNotNull);
      expect(meta.trackFingerprint, trackFingerprint(parsed.points));
    });
  });
}
