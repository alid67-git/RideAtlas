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

/// Wraps the whole app so a small "recording in progress" pill keeps showing
/// on every other screen while a ride is being tracked - since [GpsRecorder]
/// now lives above the Navigator (see main.dart), leaving [RecordScreen]
/// no longer stops the recording, so there needs to be a way back to it from
/// wherever the user ends up.
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
                right: 0,
                top: 0,
                bottom: 0,
                child: SafeArea(
                  child: Align(
                    alignment: Alignment.centerRight,
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

class _RecordingPill extends StatelessWidget {
  const _RecordingPill({required this.isPaused});

  final bool isPaused;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: l10n.recordingTapToReturn,
        child: Material(
          color: isPaused ? Colors.black54 : Colors.red,
          borderRadius: BorderRadius.circular(20),
          elevation: 4,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => rootNavigatorKey.currentState?.push(
              MaterialPageRoute(builder: (_) => const RecordScreen()),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Icon(Icons.fiber_manual_record, color: Colors.white, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}
