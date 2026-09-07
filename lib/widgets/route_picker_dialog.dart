import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/gpx_route.dart';

/// Shared "Hepsi + checkbox list" route picker, used everywhere a rider
/// chooses which saved routes to show on a map (recording overlay, the
/// multi-route viewer's reselect pill, and the home map's "Rota seç...").
/// Kept in one place so the three call sites can't drift out of sync again.
Future<Set<String>?> showRoutePickerDialog({
  required BuildContext context,
  required List<GpxRoute> routes,
  required Set<String> initiallySelected,
}) {
  final l10n = AppLocalizations.of(context)!;
  final selected = Set<String>.from(initiallySelected);
  return showDialog<Set<String>>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setLocal) {
          final allSelected =
              routes.isNotEmpty && selected.length == routes.length;
          return AlertDialog(
            title: Text(l10n.recordOverlayTitle),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: routes.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return CheckboxListTile(
                      value: allSelected,
                      title: Text(l10n.recordOverlaySelectAll),
                      onChanged: (_) => setLocal(() {
                        if (allSelected) {
                          selected.clear();
                        } else {
                          selected
                            ..clear()
                            ..addAll(routes.map((r) => r.id));
                        }
                      }),
                    );
                  }
                  final route = routes[i - 1];
                  return CheckboxListTile(
                    value: selected.contains(route.id),
                    title: Text(route.name),
                    subtitle: Text('${route.distanceKm.toStringAsFixed(1)} km'),
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
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, selected),
                child: Text(l10n.recordOverlayShow),
              ),
            ],
          );
        },
      );
    },
  );
}
