import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Typical Android 3-button bar when the OS reports no inset (Samsung
/// One UI + edge-to-edge has done this). Gesture-only phones usually
/// report a real [viewPadding]; this is only the fallback.
const kAndroidNavBarFallback = 24.0;

/// How far to lift the Flutter view above the system navigation / gesture
/// bar. Uses the OS inset when it is reported; on Android, if both insets
/// are 0 (seen on some Samsung builds), adds [kAndroidNavBarFallback] so
/// map FABs and the attribution (i) do not sit on the back/recents bar.
@visibleForTesting
double systemNavBarLift({
  required double viewPadding,
  required double padding,
  required bool isAndroid,
}) {
  final reported = viewPadding > padding ? viewPadding : padding;
  if (reported > 0) return reported;
  return isAndroid ? kAndroidNavBarFallback : 0;
}

/// MediaAtlas-style: keep the whole app (map chrome included) above the
/// Android system navigation bar instead of drawing icons on top of it.
class SystemNavBarLift extends StatelessWidget {
  const SystemNavBarLift({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final lift = systemNavBarLift(
      viewPadding: mq.viewPadding.bottom,
      padding: mq.padding.bottom,
      isAndroid: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
    );
    if (lift <= 0) return child;
    return MediaQuery(
      data: mq.copyWith(
        padding: mq.padding.copyWith(bottom: 0),
        viewPadding: mq.viewPadding.copyWith(bottom: 0),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: lift),
        child: child,
      ),
    );
  }
}
