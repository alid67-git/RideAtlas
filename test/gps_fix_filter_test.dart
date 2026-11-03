import 'package:flutter_test/flutter_test.dart';
import 'package:rideatlas/services/gps_fix_filter.dart';

void main() {
  group('isGpsHopWithinNoise', () {
    test('indoor 40 m hop with 40 m accuracy is still sitting at home', () {
      // ~40 m in 2 s is the 72 km/h "max speed" from a phone that never left
      // the house — inside the reported accuracy circle, so not a ride.
      expect(
        isGpsHopWithinNoise(meters: 40, accuracyMeters: 40),
        isTrue,
      );
      expect(
        isGpsHopWithinNoise(meters: 25, accuracyMeters: 40),
        isTrue,
      );
    });

    test('same 25 m hop outdoors (8 m accuracy) is real movement', () {
      expect(
        isGpsHopWithinNoise(meters: 25, accuracyMeters: 8),
        isFalse,
      );
    });

    test('unknown accuracy still ignores small wobble', () {
      expect(
        isGpsHopWithinNoise(meters: 10, accuracyMeters: 0),
        isTrue,
      );
      expect(
        isGpsHopWithinNoise(meters: 20, accuracyMeters: 0),
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
