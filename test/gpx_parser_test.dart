import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rideatlas/models/track_point.dart';
import 'package:rideatlas/services/gpx_parser.dart';

TrackPoint _pt(double lat, double lon, DateTime time) =>
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
  });
}
