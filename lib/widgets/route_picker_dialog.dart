import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/gpx_route.dart';
import '../services/daily_analysis.dart' show colorForDay;

/// Shared route picker, used everywhere a rider chooses which saved routes
/// to show on a map (recording overlay, the multi-route viewer's reselect
/// pill, and the home map's "Rota seç..."). Kept in one place so the three
/// call sites can't drift out of sync again.
///
/// A bottom sheet rather than a boxed [AlertDialog]: "Hepsi" and the running
/// selection count stay pinned above the scrolling list instead of being
/// just another row you can scroll past, and each route gets a color swatch
/// previewing the same color it's drawn in once shown on the map.
Future<Set<String>?> showRoutePickerDialog({
  required BuildContext context,
  required List<GpxRoute> routes,
  required Set<String> initiallySelected,
}) {
  final l10n = AppLocalizations.of(context)!;
  final selected = Set<String>.from(initiallySelected);
  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setLocal) {
          final allSelected =
              routes.isNotEmpty && selected.length == routes.length;
          return FractionallySizedBox(
            heightFactor: 0.85,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.recordOverlayTitle,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  child: CheckboxListTile(
                    value: allSelected,
                    title: Text(
                      l10n.recordOverlaySelectAll,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    secondary: Text(
                      '${selected.length}/${routes.length}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    onChanged: routes.isEmpty
                        ? null
                        : (_) => setLocal(() {
                            if (allSelected) {
                              selected.clear();
                            } else {
                              selected
                                ..clear()
                                ..addAll(routes.map((r) => r.id));
                            }
                          }),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: routes.length,
                    itemBuilder: (context, i) {
                      final route = routes[i];
                      return CheckboxListTile(
                        value: selected.contains(route.id),
                        title: Text(route.name),
                        subtitle: Text(
                          '${route.distanceKm.toStringAsFixed(1)} km',
                        ),
                        secondary: CircleAvatar(
                          radius: 7,
                          backgroundColor: colorForDay(i),
                        ),
                        onChanged: (v) => setLocal(() {
                          if (v == true) {
                            selected.add(route.id);
                          } else {
                            selected.remove(route.id);
                          }
                        }),
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(l10n.cancel),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: selected.isEmpty
                                ? null
                                : () => Navigator.pop(context, selected),
                            child: Text(
                              l10n.recordOverlayShowCount(selected.length),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
