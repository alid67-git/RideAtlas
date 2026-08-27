import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/gpx_route.dart';

class RouteCard extends StatelessWidget {
  const RouteCard({
    super.key,
    required this.route,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectedChanged,
  });

  final GpxRoute route;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  /// When true, tapping the card toggles [selected] instead of calling
  /// [onTap], and a checkbox replaces the route icon / popup menu.
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool>? onSelectedChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final dateStr = DateFormat(
      'd MMM yyyy',
      Localizations.localeOf(context).languageCode,
    ).format(route.recordedAt);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: selectionMode
            ? () => onSelectedChanged?.call(!selected)
            : onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              if (selectionMode)
                Checkbox(
                  value: selected,
                  onChanged: (v) => onSelectedChanged?.call(v ?? false),
                )
              else
                CircleAvatar(
                  radius: 24,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    Icons.route,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      route.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(dateStr, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        _StatChip(
                          icon: Icons.straighten,
                          label: '${route.distanceKm.toStringAsFixed(1)} km',
                        ),
                        if (route.elevationGainMeters > 0)
                          _StatChip(
                            icon: Icons.trending_up,
                            label: '${route.elevationGainMeters.round()} m',
                          ),
                        if (route.duration != null)
                          _StatChip(
                            icon: Icons.schedule,
                            label: _formatDuration(l10n, route.duration!),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!selectionMode)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'rename') onRename();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'rename', child: Text(l10n.rename)),
                    PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDuration(AppLocalizations l10n, Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return l10n.durationHoursMinutes(h, m);
    return l10n.durationMinutes(m);
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.outline),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
