import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../l10n/gen/app_localizations.dart';
import '../services/daily_analysis.dart';

/// Midpoint of a day's track for map labels.
LatLng dayLabelAnchor(DayStats day) {
  final pts = day.points;
  if (pts.isEmpty) {
    return const LatLng(0, 0);
  }
  if (pts.length == 1) return pts.first.latLng;
  return pts[pts.length ~/ 2].latLng;
}

String _formatDuration(AppLocalizations l10n, Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) return l10n.durationHoursMinutes(h, m);
  if (m > 0) return l10n.durationMinutesSeconds(m, s);
  return l10n.durationSeconds(s);
}

/// Full-screen-ish bottom sheet: one calendar day's km and stats.
Future<void> showDayDetailSheet({
  required BuildContext context,
  required DayStats day,
  VoidCallback? onShowOnlyThisDay,
  VoidCallback? onShowAllDays,
  /// Live recording: open note/photo pin after closing this sheet.
  VoidCallback? onAddNote,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DayDetailSheet(
      day: day,
      onShowOnlyThisDay: onShowOnlyThisDay,
      onShowAllDays: onShowAllDays,
      onAddNote: onAddNote,
    ),
  );
}

class DayDetailSheet extends StatelessWidget {
  const DayDetailSheet({
    super.key,
    required this.day,
    this.onShowOnlyThisDay,
    this.onShowAllDays,
    this.onAddNote,
  });

  final DayStats day;
  final VoidCallback? onShowOnlyThisDay;
  final VoidCallback? onShowAllDays;
  final VoidCallback? onAddNote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;
    final dateFmt = DateFormat('d MMMM yyyy, EEEE', locale);
    final bottom = MediaQuery.paddingOf(context).bottom;

    final stats = <({IconData icon, String label, String value})>[
      (
        icon: Icons.schedule,
        label: l10n.ridingDuration,
        value: day.ridingDuration == null
            ? '—'
            : _formatDuration(l10n, day.ridingDuration!),
      ),
      (
        icon: Icons.hotel,
        label: l10n.rest,
        value: day.restDuration == Duration.zero
            ? '—'
            : _formatDuration(l10n, day.restDuration),
      ),
      (
        icon: Icons.trending_up,
        label: l10n.climb,
        value: '${day.elevationGainM.round()} m',
      ),
      (
        icon: Icons.trending_down,
        label: l10n.descent,
        value: '${day.elevationLossM.round()} m',
      ),
      (
        icon: Icons.arrow_upward,
        label: l10n.maxAltitude,
        value: day.maxElevation == null
            ? '—'
            : '${day.maxElevation!.round()} m',
      ),
      (
        icon: Icons.arrow_downward,
        label: l10n.minAltitude,
        value: day.minElevation == null
            ? '—'
            : '${day.minElevation!.round()} m',
      ),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: day.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${l10n.dayLabel(day.dayNumber)} · ${dateFmt.format(day.date)}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                l10n.dayDetailSubtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${day.distanceKm.toStringAsFixed(1)} km',
                textAlign: TextAlign.center,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: day.color,
                ),
              ),
              Text(
                l10n.distance,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              for (var i = 0; i < stats.length; i += 2)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(child: _StatTile(stat: stats[i])),
                      const SizedBox(width: 10),
                      Expanded(
                        child: i + 1 < stats.length
                            ? _StatTile(stat: stats[i + 1])
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              if (day.countries.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(l10n.tabRoute, style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in day.countries)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(c),
                      ),
                  ],
                ),
              ],
              if (onAddNote != null ||
                  onShowOnlyThisDay != null ||
                  onShowAllDays != null) ...[
                const SizedBox(height: 12),
                if (onAddNote != null)
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      onAddNote!();
                    },
                    icon: const Icon(Icons.add_location_alt),
                    label: Text(l10n.dayDetailAddNote),
                  ),
                if (onShowOnlyThisDay != null) ...[
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: () {
                      Navigator.pop(context);
                      onShowOnlyThisDay!();
                    },
                    child: Text(l10n.dayDetailShowOnlyThisDay),
                  ),
                ],
                if (onShowAllDays != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      onShowAllDays!();
                    },
                    child: Text(l10n.dayFilterShowAll),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat});

  final ({IconData icon, String label, String value}) stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(stat.icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stat.label,
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  stat.value,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact map pin: day number + short date, colored like the polyline.
class DayMapLabel extends StatelessWidget {
  const DayMapLabel({
    super.key,
    required this.day,
    required this.onTap,
  });

  final DayStats day;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final short = DateFormat(
      'd MMM',
      Localizations.localeOf(context).languageCode,
    ).format(day.date);

    return GestureDetector(
      onTap: onTap,
      child: Material(
        elevation: 3,
        borderRadius: BorderRadius.circular(16),
        color: day.color,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            '${l10n.dayLabel(day.dayNumber)} · $short',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}
