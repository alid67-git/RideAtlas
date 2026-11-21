import 'package:flutter_test/flutter_test.dart';
import 'package:gopro_remote/services/app_update_controller.dart';

void main() {
  test('delayUntilNextLocalNoon before noon', () {
    final now = DateTime(2026, 11, 8, 10, 15);
    final delay = delayUntilNextLocalNoon(now);
    expect(delay, const Duration(hours: 1, minutes: 45));
  });

  test('delayUntilNextLocalNoon after noon goes to tomorrow', () {
    final now = DateTime(2026, 11, 8, 12, 0);
    final delay = delayUntilNextLocalNoon(now);
    expect(delay, const Duration(hours: 24));
  });
}
