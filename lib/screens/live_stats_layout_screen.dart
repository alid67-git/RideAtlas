import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../repositories/live_stats_layout_controller.dart';

/// Lets the rider reorder and show/hide the stat cards on the record
/// screen's live info page (everything below the speed number) - requested
/// so riders who don't care about, say, climb/descent while riding can
/// drop it and move what they do care about higher up.
class LiveStatsLayoutScreen extends StatelessWidget {
  const LiveStatsLayoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = context.watch<LiveStatsLayoutController>();
    final order = controller.order;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.liveStatsLayoutTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              l10n.liveStatsLayoutHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: order.length,
              onReorderItem: (oldIndex, newIndex) {
                final newOrder = List.of(order);
                final key = newOrder.removeAt(oldIndex);
                newOrder.insert(newIndex, key);
                controller.setOrder(newOrder);
              },
              itemBuilder: (context, index) {
                final key = order[index];
                final visible = controller.isVisible(key);
                return SwitchListTile(
                  key: ValueKey(key),
                  secondary: ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle),
                  ),
                  title: Row(
                    children: [
                      Icon(liveStatIcon(key), size: 20),
                      const SizedBox(width: 12),
                      Text(liveStatLabel(key, l10n)),
                    ],
                  ),
                  value: visible,
                  onChanged: (v) => controller.setVisible(key, v),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
