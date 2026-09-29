import 'package:flutter_test/flutter_test.dart';
import 'package:rideatlas/services/gps_recorder.dart';

void main() {
  group('effectiveRecordingSpeedKmh', () {
    test('caps indoor Doppler crawl when not covering ground', () {
      expect(
        effectiveRecordingSpeedKmh(dopplerKmh: 3.5, displacementKmh: 0.4),
        0.4,
      );
    });

    test('leaves real walking speed alone when Doppler and ground agree', () {
      expect(
        effectiveRecordingSpeedKmh(dopplerKmh: 4.0, displacementKmh: 3.8),
        3.8,
      );
    });

    test('does not invent speed when Doppler is already near zero', () {
      expect(
        effectiveRecordingSpeedKmh(dopplerKmh: 0.2, displacementKmh: 4.0),
        0.2,
      );
    });
  });
}
