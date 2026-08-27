import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../screens/record_screen.dart';
import '../services/gps_recorder.dart';

/// True while [RecordScreen] itself is the visible screen - toggled from its
/// own initState/dispose. Used to hide [RecordingRowIcon] when it would
/// just be sitting on top of the real recording UI.
final recordScreenVisible = ValueNotifier<bool>(false);

/// A small blinking red icon that drops into a screen's own top icon row
/// (same size/style as the other round icon buttons there) while a
/// recording is running somewhere else in the app - tapping it jumps back
/// to [RecordScreen]. Renders as nothing while idle, or while RecordScreen
/// itself is the visible screen.
///
/// This used to be a single overlay floating above every screen, positioned
/// independently of each screen's own controls - which meant it had no way
/// to know what else lived in that corner, and ended up sitting on top of
/// (hiding) the settings gear icon on every screen. Being an ordinary row
/// item instead means it just takes its place in the row like any other
/// icon, pushing its neighbors along like every other icon.
class RecordingRowIcon extends StatelessWidget {
  const RecordingRowIcon({super.key});

  @override
  Widget build(BuildContext context) {
    final recorder = context.watch<GpsRecorder>();
    if (recorder.isIdle) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: recordScreenVisible,
      builder: (context, visible, _) {
        if (visible) return const SizedBox.shrink();
        return _BlinkingRecIcon(isPaused: recorder.isPaused);
      },
    );
  }
}

class _BlinkingRecIcon extends StatefulWidget {
  const _BlinkingRecIcon({required this.isPaused});

  final bool isPaused;

  @override
  State<_BlinkingRecIcon> createState() => _BlinkingRecIconState();
}

class _BlinkingRecIconState extends State<_BlinkingRecIcon>
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
    final button = Material(
      color: Colors.red.shade700,
      shape: const CircleBorder(),
      elevation: 2,
      child: IconButton(
        tooltip: l10n.recordingTapToReturn,
        icon: Icon(
          widget.isPaused ? Icons.pause : Icons.fiber_manual_record,
          color: Colors.white,
        ),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            // Red REC icon → text/stats (info) page of the active ride.
            builder: (_) => const RecordScreen(initialShowMap: false),
          ),
        ),
      ),
    );
    if (widget.isPaused) return button;
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.35).animate(_blink),
      child: button,
    );
  }
}
