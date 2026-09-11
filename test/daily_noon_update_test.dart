import 'package:flutter_test/flutter_test.dart';

import 'package:rideatlas/services/app_update_controller.dart';

void main() {
  group('delayUntilNextLocalNoon', () {
    test('before noon today → same calendar day 12:00', () {
      final now = DateTime(2026, 9, 11, 9, 30);
      final delay = delayUntilNextLocalNoon(now);
      expect(now.add(delay), DateTime(2026, 9, 11, 12));
    });

    test('exactly noon → tomorrow 12:00 (not a zero-delay loop)', () {
      final now = DateTime(2026, 9, 11, 12);
      final delay = delayUntilNextLocalNoon(now);
      expect(now.add(delay), DateTime(2026, 9, 12, 12));
    });

    test('after noon → tomorrow 12:00', () {
      final now = DateTime(2026, 9, 11, 18, 5, 30);
      final delay = delayUntilNextLocalNoon(now);
      expect(now.add(delay), DateTime(2026, 9, 12, 12));
    });
  });
}
