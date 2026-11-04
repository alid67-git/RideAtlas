import 'package:flutter_test/flutter_test.dart';
import 'package:rideatlas/widgets/system_nav_bar_lift.dart';

void main() {
  test('uses the larger reported inset when the OS provides one', () {
    expect(
      systemNavBarLift(viewPadding: 48, padding: 16, isAndroid: true),
      48,
    );
    expect(
      systemNavBarLift(viewPadding: 20, padding: 20, isAndroid: false),
      20,
    );
  });

  test('falls back on Android when Samsung reports no inset', () {
    expect(
      systemNavBarLift(viewPadding: 0, padding: 0, isAndroid: true),
      kAndroidNavBarFallback,
    );
    expect(
      systemNavBarLift(viewPadding: 0, padding: 0, isAndroid: false),
      0,
    );
  });
}
