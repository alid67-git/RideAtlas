import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../repositories/satellite_visibility_controller.dart';
import '../services/satellite_info.dart';

/// Small pill showing how many GPS satellites are currently used in the
/// fix (see satellite_info.dart) - hides itself entirely if the platform
/// doesn't support it, no reading has arrived yet, or the user turned it
/// off in Settings > "Uydu sayısını göster".
class SatelliteCountBadge extends StatefulWidget {
  const SatelliteCountBadge({super.key});

  @override
  State<SatelliteCountBadge> createState() => _SatelliteCountBadgeState();
}

class _SatelliteCountBadgeState extends State<SatelliteCountBadge> {
  static const _pollInterval = Duration(seconds: 2);

  int? _count;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  Future<void> _poll() async {
    final count = await currentSatelliteCount();
    if (mounted) setState(() => _count = count);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = context.watch<SatelliteVisibilityController>().visible;
    final count = _count;
    if (!visible || count == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    // 4 satellites is the minimum GPS needs for a 3D fix - below that, a
    // position isn't reliable yet.
    final good = count >= 4;
    final color = good ? Colors.green.shade600 : Colors.red.shade600;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.satellite_alt, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
