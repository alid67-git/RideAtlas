import 'package:flutter/material.dart';

/// Compact download progress for the update banner (MedyaAtlas-style %).
class AppUpdateProgressStrip extends StatelessWidget {
  const AppUpdateProgressStrip({
    super.key,
    required this.received,
    required this.total,
    this.title = 'Güncelleme indiriliyor',
  });

  final int received;
  final int total;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasTotal = total > 0;
    final fraction = hasTotal
        ? (received / total).clamp(0.0, 1.0)
        : null;
    final percentLabel = hasTotal
        ? '%${(fraction! * 100).round()}'
        : '${(received / (1024 * 1024)).toStringAsFixed(1)} MB';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            color: theme.colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: fraction,
          backgroundColor: theme.colorScheme.onPrimaryContainer.withValues(
            alpha: 0.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$percentLabel — RideAtlas.apk',
          style: TextStyle(
            color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.85),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
