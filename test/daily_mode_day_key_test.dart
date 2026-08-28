import 'package:flutter_test/flutter_test.dart';
import 'package:rideatlas/repositories/daily_mode_controller.dart';

void main() {
  test('dayKey uses local calendar yyyy-MM-dd', () {
    final local = DateTime(2026, 8, 28, 23, 59);
    expect(DailyModeController.dayKey(local), '2026-08-28');

    final next = DateTime(2026, 8, 29, 0, 1);
    expect(DailyModeController.dayKey(next), '2026-08-29');
  });

  test('dayKey pads month and day', () {
    expect(DailyModeController.dayKey(DateTime(2026, 1, 5)), '2026-01-05');
  });
}
