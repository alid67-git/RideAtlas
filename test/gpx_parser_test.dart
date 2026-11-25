import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rideatlas/models/track_point.dart';
import 'package:rideatlas/services/gpx_parser.dart';

TrackPoint _pt(double lat, double lon, [DateTime? time]) =>
    TrackPoint(latLng: LatLng(lat, lon), time: time);

void main() {
  group('findExcursionPointIndices', () {
    test('flags a cluster of points that jump away and snap back', () {
      final start = DateTime(2026, 8, 13, 9, 0, 0);
      final points = <TrackPoint>[
        // A few real, slowly-drifting points while stationary.
        _pt(41.0684, 29.0068, start),
        _pt(41.06841, 29.00681, start.add(const Duration(seconds: 6))),
        _pt(41.06839, 29.00679, start.add(const Duration(seconds: 12))),
        // Glitch: jumps ~1.7km away and stays frozen there for a while.
        _pt(41.08357, 29.00498, start.add(const Duration(seconds: 56))),
        _pt(41.08357, 29.00498, start.add(const Duration(seconds: 62))),
        _pt(41.08357, 29.00498, start.add(const Duration(seconds: 68))),
        // Snaps back to (almost) where it left off.
        _pt(41.06841, 29.00680, start.add(const Duration(seconds: 105))),
        _pt(41.06840, 29.00679, start.add(const Duration(seconds: 111))),
      ];

      final flagged = findExcursionPointIndices(points);

      expect(flagged, [3, 4, 5]);
    });

    test('does not flag ordinary stationary GPS jitter', () {
      final start = DateTime(2026, 8, 13, 9, 0, 0);
      final points = <TrackPoint>[
        for (var i = 0; i < 30; i++)
          _pt(
            41.0684 + (i.isEven ? 0.00005 : -0.00005),
            29.0068 + (i.isEven ? -0.00004 : 0.00004),
            start.add(Duration(seconds: i * 2)),
          ),
      ];

      expect(findExcursionPointIndices(points), isEmpty);
    });

    test('does not flag sustained real movement that never returns', () {
      final start = DateTime(2026, 8, 13, 9, 0, 0);
      final points = <TrackPoint>[
        for (var i = 0; i < 20; i++)
          // ~1km every 60s along a straight line = 60 km/h, continuing on
          // rather than looping back.
          _pt(41.0 + i * 0.009, 29.0, start.add(Duration(seconds: i * 60))),
      ];

      expect(findExcursionPointIndices(points), isEmpty);
    });

    test('keeps untimed Pak Bara ↔ Koh Lipe ferry round trip', () {
      // Mirrors the uploaded South Thailand GPX: no timestamps, boat out
      // and back. Old logic treated the return to the pier as a glitch and
      // wiped Lipe + both sea legs.
      final points = <TrackPoint>[
        _pt(6.8417, 99.7485), // Pak Bara
        _pt(6.80, 99.70),
        _pt(6.75, 99.62),
        _pt(6.66, 99.50),
        _pt(6.53, 99.36),
        _pt(6.4870, 99.3040), // Koh Lipe
        _pt(6.4871, 99.3041),
        _pt(6.53, 99.36),
        _pt(6.66, 99.50),
        _pt(6.75, 99.62),
        _pt(6.80, 99.70),
        _pt(6.8417, 99.7485), // back to Pak Bara
      ];

      expect(findExcursionPointIndices(points), isEmpty);
      expect(findImplausiblePointIndices(points), isEmpty);
      expect(filterImplausiblePoints(points), hasLength(points.length));
    });
  });

  group('findImplausiblePointIndices', () {
    test('still catches an instantly-impossible single spike', () {
      final start = DateTime(2026, 8, 13, 9, 0, 0);
      final points = <TrackPoint>[
        _pt(41.0, 29.0, start),
        // ~500km away one second later - impossible outright.
        _pt(45.5, 29.0, start.add(const Duration(seconds: 1))),
        _pt(41.00001, 29.00001, start.add(const Duration(seconds: 2))),
      ];

      expect(findImplausiblePointIndices(points), contains(1));
    });

    test('flags an isolated hop above 120 km/h as outlier', () {
      final start = DateTime(2026, 8, 13, 9, 0, 0);
      // ~0.0015° lat ≈ 167 m in 4 s ≈ 150 km/h, then crawl — lone spike.
      final points = <TrackPoint>[
        _pt(41.0, 29.0, start),
        _pt(41.0015, 29.0, start.add(const Duration(seconds: 4))),
        _pt(41.00152, 29.0, start.add(const Duration(seconds: 8))),
      ];

      expect(findImplausiblePointIndices(points), contains(1));
      expect(
        filterImplausiblePoints(points).map((p) => p.latLng.latitude).toList(),
        [41.0, 41.00152],
      );
    });

    test('keeps sustained consecutive hops above 120 km/h', () {
      final start = DateTime(2026, 8, 13, 9, 0, 0);
      // ~140 km/h along a line for several fixes — real fast riding.
      final points = <TrackPoint>[
        for (var i = 0; i < 8; i++)
          _pt(
            41.0 + i * 0.00125,
            29.0,
            start.add(Duration(seconds: i * 4)),
          ),
      ];

      expect(findImplausiblePointIndices(points), isEmpty);
    });

    test('keeps a final hop above 120 when track ends mid-speed', () {
      final start = DateTime(2026, 8, 13, 9, 0, 0);
      final points = <TrackPoint>[
        for (var i = 0; i < 4; i++)
          _pt(
            41.0 + i * 0.00125,
            29.0,
            start.add(Duration(seconds: i * 4)),
          ),
      ];

      expect(findImplausiblePointIndices(points), isEmpty);
    });

    test('keeps a long ferry-like hop even if implied speed is >120', () {
      final start = DateTime(2026, 8, 13, 9, 0, 0);
      // Pak Bara-ish → Koh Lipe-ish (~60+ km) in 25 minutes ≈ 150 km/h.
      // Sparse boat GPS used to be dropped as an "isolated spike".
      final points = <TrackPoint>[
        _pt(6.8417, 99.7485, start),
        _pt(6.4870, 99.3040, start.add(const Duration(minutes: 25))),
        _pt(6.4871, 99.3041, start.add(const Duration(minutes: 26))),
      ];

      expect(findImplausiblePointIndices(points), isEmpty);
      expect(filterImplausiblePoints(points), hasLength(3));
    });
  });
}
