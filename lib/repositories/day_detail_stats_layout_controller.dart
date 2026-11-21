import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../l10n/gen/app_localizations.dart';

const _metaBoxName = 'rideatlas_meta';
const _orderKey = 'day_detail_stats_order';
const _hiddenKey = 'day_detail_stats_hidden';

/// Stat cards on the multi-day day-detail sheet / fullscreen day map.
enum DayDetailStatKey {
  ridingDuration,
  rest,
  averageSpeed,
  maxSpeed,
  climb,
  descent,
  maxAltitude,
  minAltitude,
}

/// Default order: speeds near the top; climb/descent last (and hidden by
/// default — still available from the layout sheet).
const List<DayDetailStatKey> defaultDayDetailStatOrder = [
  DayDetailStatKey.ridingDuration,
  DayDetailStatKey.rest,
  DayDetailStatKey.averageSpeed,
  DayDetailStatKey.maxSpeed,
  DayDetailStatKey.maxAltitude,
  DayDetailStatKey.minAltitude,
  DayDetailStatKey.climb,
  DayDetailStatKey.descent,
];

const Set<DayDetailStatKey> defaultDayDetailHiddenStats = {
  DayDetailStatKey.climb,
  DayDetailStatKey.descent,
};

IconData dayDetailStatIcon(DayDetailStatKey key) {
  switch (key) {
    case DayDetailStatKey.ridingDuration:
      return Icons.schedule;
    case DayDetailStatKey.rest:
      return Icons.hotel;
    case DayDetailStatKey.averageSpeed:
      return Icons.equalizer;
    case DayDetailStatKey.maxSpeed:
      return Icons.bolt;
    case DayDetailStatKey.climb:
      return Icons.trending_up;
    case DayDetailStatKey.descent:
      return Icons.trending_down;
    case DayDetailStatKey.maxAltitude:
      return Icons.arrow_upward;
    case DayDetailStatKey.minAltitude:
      return Icons.arrow_downward;
  }
}

String dayDetailStatLabel(DayDetailStatKey key, AppLocalizations l10n) {
  switch (key) {
    case DayDetailStatKey.ridingDuration:
      return l10n.ridingDuration;
    case DayDetailStatKey.rest:
      return l10n.rest;
    case DayDetailStatKey.averageSpeed:
      return l10n.averageSpeedLabel;
    case DayDetailStatKey.maxSpeed:
      return l10n.maxSpeed;
    case DayDetailStatKey.climb:
      return l10n.climb;
    case DayDetailStatKey.descent:
      return l10n.descent;
    case DayDetailStatKey.maxAltitude:
      return l10n.maxAltitude;
    case DayDetailStatKey.minAltitude:
      return l10n.minAltitude;
  }
}

/// Persisted order + visibility for day-detail stat tiles.
class DayDetailStatsLayoutController extends ChangeNotifier {
  List<DayDetailStatKey> _order = List.of(defaultDayDetailStatOrder);
  Set<DayDetailStatKey> _hidden = Set.of(defaultDayDetailHiddenStats);

  List<DayDetailStatKey> get order => List.unmodifiable(_order);

  List<DayDetailStatKey> get visibleOrder =>
      _order.where((k) => !_hidden.contains(k)).toList(growable: false);

  bool isVisible(DayDetailStatKey key) => !_hidden.contains(key);

  Future<void> load() async {
    final box = await Hive.openBox<String>(_metaBoxName);
    final orderStored = box.get(_orderKey);
    if (orderStored != null && orderStored.isNotEmpty) {
      final parsed = <DayDetailStatKey>[];
      for (final name in orderStored.split(',')) {
        final match = DayDetailStatKey.values.where((k) => k.name == name);
        if (match.isNotEmpty) parsed.add(match.first);
      }
      for (final key in defaultDayDetailStatOrder) {
        if (!parsed.contains(key)) parsed.add(key);
      }
      if (parsed.length == defaultDayDetailStatOrder.length) {
        _order = parsed;
      }
    }
    final hiddenStored = box.get(_hiddenKey);
    if (hiddenStored != null) {
      _hidden = hiddenStored
          .split(',')
          .where((n) => n.isNotEmpty)
          .map((n) => DayDetailStatKey.values.where((k) => k.name == n))
          .where((m) => m.isNotEmpty)
          .map((m) => m.first)
          .toSet();
    }
    notifyListeners();
  }

  Future<void> setOrder(List<DayDetailStatKey> newOrder) async {
    _order = newOrder;
    notifyListeners();
    final box = await Hive.openBox<String>(_metaBoxName);
    await box.put(_orderKey, newOrder.map((k) => k.name).join(','));
  }

  Future<void> swap(DayDetailStatKey a, DayDetailStatKey b) async {
    if (a == b) return;
    final newOrder = List.of(_order);
    final indexA = newOrder.indexOf(a);
    final indexB = newOrder.indexOf(b);
    if (indexA == -1 || indexB == -1) return;
    newOrder[indexA] = b;
    newOrder[indexB] = a;
    await setOrder(newOrder);
  }

  Future<void> setVisible(DayDetailStatKey key, bool visible) async {
    if (visible) {
      _hidden.remove(key);
    } else {
      // Keep at least two visible tiles so the panel never looks empty.
      if (_order.where((k) => !_hidden.contains(k) && k != key).length < 2) {
        return;
      }
      _hidden.add(key);
    }
    notifyListeners();
    final box = await Hive.openBox<String>(_metaBoxName);
    await box.put(_hiddenKey, _hidden.map((k) => k.name).join(','));
  }
}
