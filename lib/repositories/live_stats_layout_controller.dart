import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../l10n/gen/app_localizations.dart';

const _metaBoxName = 'rideatlas_meta';
const _orderKey = 'live_stats_order';
const _hiddenKey = 'live_stats_hidden';

/// Every stat card the record screen's live info page can show below the
/// speed number - the "Toplam süre" hero strip and the speed number itself
/// aren't included here, they're always shown and not user-reorderable.
enum LiveStatKey {
  ridingDuration,
  distance,
  restDuration,
  currentAltitude,
  maxAltitude,
  minAltitude,
  timeSinceLastRest,
  averageSpeed,
  maxSpeed,
  climb,
  descent,
}

/// Order the app ships with - matches what the screen looked like before
/// this became configurable.
const List<LiveStatKey> defaultLiveStatOrder = [
  LiveStatKey.ridingDuration,
  LiveStatKey.distance,
  LiveStatKey.restDuration,
  LiveStatKey.currentAltitude,
  LiveStatKey.maxAltitude,
  LiveStatKey.minAltitude,
  LiveStatKey.timeSinceLastRest,
  LiveStatKey.averageSpeed,
  LiveStatKey.maxSpeed,
  LiveStatKey.climb,
  LiveStatKey.descent,
];

IconData liveStatIcon(LiveStatKey key) {
  switch (key) {
    case LiveStatKey.ridingDuration:
      return Icons.timer_outlined;
    case LiveStatKey.distance:
      return Icons.route;
    case LiveStatKey.restDuration:
      return Icons.pause_circle_outline;
    case LiveStatKey.currentAltitude:
      return Icons.terrain;
    case LiveStatKey.maxAltitude:
      return Icons.arrow_upward;
    case LiveStatKey.minAltitude:
      return Icons.arrow_downward;
    case LiveStatKey.timeSinceLastRest:
      return Icons.hourglass_bottom;
    case LiveStatKey.averageSpeed:
      return Icons.equalizer;
    case LiveStatKey.maxSpeed:
      return Icons.bolt;
    case LiveStatKey.climb:
      return Icons.trending_up;
    case LiveStatKey.descent:
      return Icons.trending_down;
  }
}

String liveStatLabel(LiveStatKey key, AppLocalizations l10n) {
  switch (key) {
    case LiveStatKey.ridingDuration:
      return l10n.netDurationLabel;
    case LiveStatKey.distance:
      return l10n.distance;
    case LiveStatKey.restDuration:
      return l10n.restDurationLabel;
    case LiveStatKey.currentAltitude:
      return l10n.currentAltitudeLabel;
    case LiveStatKey.maxAltitude:
      return l10n.maxAltitude;
    case LiveStatKey.minAltitude:
      return l10n.minAltitude;
    case LiveStatKey.timeSinceLastRest:
      return l10n.timeSinceLastRestLabel;
    case LiveStatKey.averageSpeed:
      return l10n.averageSpeedLabel;
    case LiveStatKey.maxSpeed:
      return l10n.maxSpeed;
    case LiveStatKey.climb:
      return l10n.climb;
    case LiveStatKey.descent:
      return l10n.descent;
  }
}

/// Lets riders reorder and show/hide the stat cards on the record screen's
/// live info page, persisted so it sticks across recordings/app restarts.
/// Previously the order was hard-coded and every card always showed -
/// requested so riders can drop cards they never look at and put the ones
/// they care about first.
class LiveStatsLayoutController extends ChangeNotifier {
  List<LiveStatKey> _order = List.of(defaultLiveStatOrder);
  Set<LiveStatKey> _hidden = {};

  /// Full order, including hidden entries - used by the settings screen so
  /// hidden cards still show up (toggled off) rather than disappearing.
  List<LiveStatKey> get order => List.unmodifiable(_order);

  /// Order filtered to only the cards currently shown - what the record
  /// screen actually renders.
  List<LiveStatKey> get visibleOrder =>
      _order.where((k) => !_hidden.contains(k)).toList(growable: false);

  bool isVisible(LiveStatKey key) => !_hidden.contains(key);

  Future<void> load() async {
    final box = await Hive.openBox<String>(_metaBoxName);
    final orderStored = box.get(_orderKey);
    if (orderStored != null && orderStored.isNotEmpty) {
      final names = orderStored.split(',');
      final parsed = <LiveStatKey>[];
      for (final name in names) {
        final match = LiveStatKey.values.where((k) => k.name == name);
        if (match.isNotEmpty) parsed.add(match.first);
      }
      // Any key added to the enum after this was saved (app update) still
      // needs to show up somewhere - append it at the end instead of
      // silently dropping it.
      for (final key in defaultLiveStatOrder) {
        if (!parsed.contains(key)) parsed.add(key);
      }
      if (parsed.length == defaultLiveStatOrder.length) _order = parsed;
    }
    final hiddenStored = box.get(_hiddenKey);
    if (hiddenStored != null) {
      _hidden = hiddenStored
          .split(',')
          .where((n) => n.isNotEmpty)
          .map((n) => LiveStatKey.values.where((k) => k.name == n))
          .where((m) => m.isNotEmpty)
          .map((m) => m.first)
          .toSet();
    }
    notifyListeners();
  }

  Future<void> setOrder(List<LiveStatKey> newOrder) async {
    _order = newOrder;
    notifyListeners();
    final box = await Hive.openBox<String>(_metaBoxName);
    await box.put(_orderKey, newOrder.map((k) => k.name).join(','));
  }

  /// Swaps two cards' positions directly - what the live info page's
  /// press-and-hold drag reorder uses (drop one card onto another), as
  /// opposed to [setOrder]'s full-list reorder used by the settings
  /// screen's drag list.
  Future<void> swap(LiveStatKey a, LiveStatKey b) async {
    if (a == b) return;
    final newOrder = List.of(_order);
    final indexA = newOrder.indexOf(a);
    final indexB = newOrder.indexOf(b);
    if (indexA == -1 || indexB == -1) return;
    newOrder[indexA] = b;
    newOrder[indexB] = a;
    await setOrder(newOrder);
  }

  Future<void> setVisible(LiveStatKey key, bool visible) async {
    if (visible) {
      _hidden.remove(key);
    } else {
      _hidden.add(key);
    }
    notifyListeners();
    final box = await Hive.openBox<String>(_metaBoxName);
    await box.put(_hiddenKey, _hidden.map((k) => k.name).join(','));
  }
}
