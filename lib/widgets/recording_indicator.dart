import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../main.dart' show rootNavigatorKey;
import '../screens/record_screen.dart';
import '../services/gps_recorder.dart';

/// True while [RecordScreen] itself is the visible screen - toggled from its
/// own initState/dispose. Used to hide the floating indicator when it would
/// just be sitting on top of the real recording UI.
final recordScreenVisible = ValueNotifier<bool>(false);

/// Wraps the whole app so a small blinking "REC" pill keeps showing in the
/// top-right corner of every other screen while a ride is being tracked -
/// since [GpsRecorder] now lives above the Navigator (see main.dart),
/// leaving [RecordScreen] no longer stops the recording, so there needs to
/// be a way back to it from wherever the user ends up. Pinned right at the
/// safe-area corner (not further down, below each screen's own icon row)
/// so it's the first thing visible, not something to notice among other
/// controls.
class RecordingIndicatorOverlay extends StatelessWidget {
  const RecordingIndicatorOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final recorder = context.watch<GpsRecorder>();
    return Stack(
      children: [
        child,
        if (!recorder.isIdle)
          ValueListenableBuilder<bool>(
            valueListenable: recordScreenVisible,
            builder: (context, visible, _) {
              if (visible) return const SizedBox.shrink();
              return Positioned(
                top: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, right: 8),
                    child: _RecordingPill(isPaused: recorder.isPaused),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _RecordingPill extends StatefulWidget {
  const _RecordingPill({required this.isPaused});

  final bool isPaused;

  @override
  State<_RecordingPill> createState() => _RecordingPillState();
}

class _RecordingPillState extends State<_RecordingPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pill = Material(
      color: Colors.red.shade700,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Colors.white, width: 1.5),
      ),
      elevation: 6,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => rootNavigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const RecordScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.isPaused ? Icons.pause : Icons.fiber_manual_record,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 6),
              const Text(
                'REC',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Tooltip(
      message: l10n.recordingTapToReturn,
      // The whole pill blinks (not just an icon inside it) so it reads as
      // "notice me" against literally any background - a map, a plain
      // white settings list, a photo - rather than blending in.
      child: widget.isPaused
          ? pill
          : FadeTransition(
              opacity: Tween(begin: 1.0, end: 0.45).animate(_blink),
              child: pill,
            ),
    );
  }
}
