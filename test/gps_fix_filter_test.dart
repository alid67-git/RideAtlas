import 'package:flutter_test/flutter_test.dart';
import 'package:rideatlas/services/gps_fix_filter.dart';

void main() {
  group('isGpsHopWithinNoise', () {
    test('indoor 40 m hop with 40 m accuracy is still sitting at home', () {
      expect(
        isGpsHopWithinNoise(meters: 40, accuracyMeters: 40),
        isTrue,
      );
      expect(
        isGpsHopWithinNoise(meters: 25, accuracyMeters: 40),
        isTrue,
      );
    });

    test('optimistic 8 m accuracy still ignores a 12 m indoor hop', () {
      // v1.4.127 used 1× accuracy (gate 8 m), so this hop was recorded and
      // showed up as ~10.8 km/h while the phone sat at home.
      expect(
        isGpsHopWithinNoise(meters: 12, accuracyMeters: 8),
        isTrue,
      );
      expect(
        isGpsHopWithinNoise(meters: 6, accuracyMeters: 8),
        isTrue,
      );
    });

    test('a 30 m hop outdoors (8 m accuracy) is real movement', () {
      expect(
        isGpsHopWithinNoise(meters: 30, accuracyMeters: 8),
        isFalse,
      );
    });

    test('riding minMeters 5 still records a 17 m outdoor hop', () {
      // Live recording uses minMeters: 5 so iPhone / sparse streams are
      // not forced to one point every 25 m (default floor).
      expect(
        isGpsHopWithinNoise(
          meters: 17,
          accuracyMeters: 8,
          minMeters: 5,
        ),
        isFalse,
      );
      expect(
        isGpsHopWithinNoise(
          meters: 12,
          accuracyMeters: 8,
          minMeters: 5,
        ),
        isTrue,
      );
    });

    test('unknown accuracy still ignores small wobble', () {
      expect(
        isGpsHopWithinNoise(meters: 10, accuracyMeters: 0),
        isTrue,
      );
      expect(
        isGpsHopWithinNoise(meters: 25, accuracyMeters: 0),
        isTrue,
      );
      expect(
        isGpsHopWithinNoise(meters: 31, accuracyMeters: 0),
        isFalse,
      );
    });
  });

  group('isGpsHopARealMoveAway', () {
    test('20 m indoor jump does not clear auto-pause', () {
      expect(
        isGpsHopARealMoveAway(meters: 20, accuracyMeters: 40),
        isFalse,
      );
      expect(
        isGpsHopARealMoveAway(meters: 79, accuracyMeters: 40),
        isFalse,
      );
      expect(
        isGpsHopARealMoveAway(meters: 80, accuracyMeters: 40),
        isTrue,
      );
    });

    test('overnight scribble stays parked until three 80 m leaves', () {
      final stay = StickyStay();
      expect(stay.consider(metersFromOrigin: 40, accuracyMeters: 8), isTrue);
      expect(stay.consider(metersFromOrigin: 70, accuracyMeters: 8), isTrue);
      expect(stay.consider(metersFromOrigin: 90, accuracyMeters: 8), isTrue);
      expect(stay.consider(metersFromOrigin: 20, accuracyMeters: 8), isTrue);
      expect(stay.locked, isTrue);
      expect(stay.consider(metersFromOrigin: 90, accuracyMeters: 8), isTrue);
      expect(stay.consider(metersFromOrigin: 95, accuracyMeters: 8), isTrue);
      expect(stay.consider(metersFromOrigin: 100, accuracyMeters: 8), isFalse);
      expect(stay.locked, isFalse);
    });

    test('outdoor walk still resumes at 20 m', () {
      expect(
        isGpsHopARealMoveAway(meters: 20, accuracyMeters: 8),
        isTrue,
      );
      expect(
        isGpsHopARealMoveAway(meters: 19, accuracyMeters: 8),
        isFalse,
      );
    });
  });
}
