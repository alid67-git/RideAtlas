import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/base_map_style.dart';
import '../repositories/day_detail_stats_layout_controller.dart';
import '../services/daily_analysis.dart';
import '../services/gpx_parser.dart';
import '../services/map_camera_fit.dart';
import '../services/track_display_simplify.dart';

const _metaBoxName = 'rideatlas_meta';
const _mapStyleKey = 'base_map_style_id';

const _dayLabelDistance = Distance();

/// Days whose midpoints fall within this radius share a stack cascade so
/// overlapping pills still peek out from under each other.
const kDayLabelClusterMeters = 180.0;
const kDayLabelStackStepX = 14.0;
const kDayLabelStackStepY = 16.0;

/// Midpoint of a day's track for map labels.
LatLng dayLabelAnchor(DayStats day) {
  final pts = day.points;
  if (pts.isEmpty) {
    return const LatLng(0, 0);
  }
  if (pts.length == 1) return pts.first.latLng;
  return pts[pts.length ~/ 2].latLng;
}

/// Pixel offsets (same order as [days]) so labels whose anchors sit nearly
/// on top of each other cascade down-right and remain partly visible.
List<Offset> dayLabelStackOffsets(
  List<DayStats> days, {
  double clusterMeters = kDayLabelClusterMeters,
}) {
  final n = days.length;
  final offsets = List<Offset>.filled(n, Offset.zero);
  if (n < 2) return offsets;

  final anchors = [for (final d in days) dayLabelAnchor(d)];
  final visited = List<bool>.filled(n, false);

  for (var i = 0; i < n; i++) {
    if (visited[i] || days[i].points.isEmpty) continue;
    final cluster = <int>[];
    final queue = <int>[i];
    visited[i] = true;
    while (queue.isNotEmpty) {
      final u = queue.removeAt(0);
      cluster.add(u);
      for (var v = 0; v < n; v++) {
        if (visited[v] || days[v].points.isEmpty) continue;
        if (_dayLabelDistance(anchors[u], anchors[v]) <= clusterMeters) {
          visited[v] = true;
          queue.add(v);
        }
      }
    }
    if (cluster.length < 2) continue;
    cluster.sort((a, b) => days[a].dayNumber.compareTo(days[b].dayNumber));
    for (var rank = 0; rank < cluster.length; rank++) {
      offsets[cluster[rank]] = Offset(
        rank * kDayLabelStackStepX,
        rank * kDayLabelStackStepY,
      );
    }
  }
  return offsets;
}

String _formatDuration(AppLocalizations l10n, Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) return l10n.durationHoursMinutes(h, m);
  if (m > 0) return l10n.durationMinutesSeconds(m, s);
  return l10n.durationSeconds(s);
}

Map<DayDetailStatKey, String> _dayStatValues(
  AppLocalizations l10n,
  DayStats day,
) {
  final speed = buildSpeedStats(day.points);
  return {
    DayDetailStatKey.ridingDuration: day.ridingDuration == null
        ? '—'
        : _formatDuration(l10n, day.ridingDuration!),
    DayDetailStatKey.rest: day.restDuration == Duration.zero
        ? '—'
        : _formatDuration(l10n, day.restDuration),
    DayDetailStatKey.averageSpeed: speed.averageMovingKmh == null
        ? '—'
        : '${speed.averageMovingKmh!.toStringAsFixed(1)} km/h',
    DayDetailStatKey.maxSpeed: speed.maxKmh == null
        ? '—'
        : '${speed.maxKmh!.toStringAsFixed(1)} km/h',
    DayDetailStatKey.climb: '${day.elevationGainM.round()} m',
    DayDetailStatKey.descent: '${day.elevationLossM.round()} m',
    DayDetailStatKey.maxAltitude: day.maxElevation == null
        ? '—'
        : '${day.maxElevation!.round()} m',
    DayDetailStatKey.minAltitude: day.minElevation == null
        ? '—'
        : '${day.minElevation!.round()} m',
  };
}

Future<void> _showDayDetailStatsLayoutSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return Consumer<DayDetailStatsLayoutController>(
        builder: (context, layout, _) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.dayDetailStatsLayoutTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.dayDetailStatsLayoutHint,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                    ),
                    child: ReorderableListView.builder(
                      shrinkWrap: true,
                      itemCount: layout.order.length,
                      onReorder: (oldIndex, newIndex) {
                        final next = List.of(layout.order);
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = next.removeAt(oldIndex);
                        next.insert(newIndex, item);
                        unawaited(layout.setOrder(next));
                      },
                      itemBuilder: (context, index) {
                        final key = layout.order[index];
                        return SwitchListTile(
                          key: ValueKey(key.name),
                          secondary: Icon(dayDetailStatIcon(key)),
                          title: Text(dayDetailStatLabel(key, l10n)),
                          value: layout.isVisible(key),
                          onChanged: (v) =>
                              unawaited(layout.setVisible(key, v)),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Widget _dayStatGrid({
  required BuildContext context,
  required DayStats day,
  required DayDetailStatsLayoutController layout,
  bool compact = false,
}) {
  final l10n = AppLocalizations.of(context)!;
  final theme = Theme.of(context);
  final values = _dayStatValues(l10n, day);
  final keys = layout.visibleOrder;
  if (keys.isEmpty) return const SizedBox.shrink();

  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < keys.length; i += 2)
        Padding(
          padding: EdgeInsets.only(bottom: i + 2 < keys.length ? 6 : 0),
          child: Row(
            children: [
              Expanded(
                child: _DraggableDayStatTile(
                  statKey: keys[i],
                  value: values[keys[i]] ?? '—',
                  layout: layout,
                  accent: day.color,
                  compact: compact,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: i + 1 < keys.length
                    ? _DraggableDayStatTile(
                        statKey: keys[i + 1],
                        value: values[keys[i + 1]] ?? '—',
                        layout: layout,
                        accent: day.color,
                        compact: compact,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      const SizedBox(height: 4),
      Text(
        l10n.dayDetailStatsReorderHint,
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

Future<BaseMapStyle> _loadMapStyle() async {
  try {
    final box = await Hive.openBox<String>(_metaBoxName);
    return findBaseMapStyle(box.get(_mapStyleKey));
  } catch (_) {
    return kBaseMapStyles.first;
  }
}

/// Bottom sheet: day stats, prev/next among [days], and a mini map of that
/// day's track (tap → fullscreen map with the same stats overlay).
Future<void> showDayDetailSheet({
  required BuildContext context,
  required DayStats day,
  /// All trip days (ordered). Defaults to `[day]`.
  List<DayStats>? days,
  /// When true, open on Day 1 even if [day] is later. Default false so a
  /// tapped day opens on that day; left/right still pages the full list.
  bool startAtFirstDay = false,
  ValueChanged<DayStats>? onShowOnlyThisDay,
  VoidCallback? onShowAllDays,
  /// Live recording: open note/photo pin after closing this sheet.
  VoidCallback? onAddNote,
  /// Called when the rider pages to another day (parent may refocus the map).
  ValueChanged<DayStats>? onDayChanged,
  /// Export this day's track (destination + format). Does not close the sheet.
  Future<void> Function(DayStats day)? onExportDay,
  /// Replace this day's track from a GPX/KML. Return true after a successful
  /// revise so the sheet can close.
  Future<bool> Function(DayStats day)? onReviseDay,
}) {
  final all = List<DayStats>.of(days ?? [day]);
  if (all.isEmpty) all.add(day);
  all.sort((a, b) => a.dayNumber.compareTo(b.dayNumber));

  var initialIndex = 0;
  if (!startAtFirstDay) {
    final i = all.indexWhere((d) => d.dayNumber == day.dayNumber);
    initialIndex = i >= 0 ? i : 0;
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DayDetailSheet(
      days: all,
      initialIndex: initialIndex,
      onShowOnlyThisDay: onShowOnlyThisDay,
      onShowAllDays: onShowAllDays,
      onAddNote: onAddNote,
      onDayChanged: onDayChanged,
      onExportDay: onExportDay,
      onReviseDay: onReviseDay,
    ),
  );
}

/// Confirms overwriting [dayLabel] with [fileName]. Returns true if confirmed.
Future<bool> confirmDayReviseDialog({
  required BuildContext context,
  required String dayLabel,
  required String fileName,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final theme = Theme.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.dayDetailReviseTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.dayDetailReviseOverwriteDayLabel,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            dayLabel,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.dayDetailReviseFromFileLabel,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            fileName,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Text(l10n.dayDetailReviseWarning),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.dayDetailReviseConfirm),
        ),
      ],
    ),
  );
  return ok == true;
}

class DayDetailSheet extends StatefulWidget {
  const DayDetailSheet({
    super.key,
    required this.days,
    required this.initialIndex,
    this.onShowOnlyThisDay,
    this.onShowAllDays,
    this.onAddNote,
    this.onDayChanged,
    this.onExportDay,
    this.onReviseDay,
  });

  final List<DayStats> days;
  final int initialIndex;
  final ValueChanged<DayStats>? onShowOnlyThisDay;
  final VoidCallback? onShowAllDays;
  final VoidCallback? onAddNote;
  final ValueChanged<DayStats>? onDayChanged;
  final Future<void> Function(DayStats day)? onExportDay;
  final Future<bool> Function(DayStats day)? onReviseDay;

  @override
  State<DayDetailSheet> createState() => _DayDetailSheetState();
}

class _DayDetailSheetState extends State<DayDetailSheet> {
  late int _index;
  BaseMapStyle _mapStyle = kBaseMapStyles.first;
  final _mapController = MapController();
  int _openedWithNoteIndex = -1;
  bool _revising = false;
  bool _exporting = false;

  DayStats get _day => widget.days[_index];

  bool get _canPrev => _index > 0;
  bool get _canNext => _index < widget.days.length - 1;

  Future<void> _runRevise() async {
    final revise = widget.onReviseDay;
    if (revise == null || _revising || _exporting) return;
    setState(() => _revising = true);
    try {
      final ok = await revise(_day);
      if (ok && mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _revising = false);
    }
  }

  Future<void> _runExport() async {
    final export = widget.onExportDay;
    if (export == null || _exporting || _revising) return;
    setState(() => _exporting = true);
    try {
      await export(_day);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.days.length - 1);
    if (widget.onAddNote != null) _openedWithNoteIndex = _index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onDayChanged?.call(_day);
      _fitDay();
    });
    unawaited(_initStyle());
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _initStyle() async {
    final style = await _loadMapStyle();
    if (!mounted) return;
    setState(() => _mapStyle = style);
  }

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= widget.days.length) return;
    setState(() => _index = next);
    widget.onDayChanged?.call(_day);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitDay();
    });
  }

  void _fitDay() {
    final pts = [for (final p in _day.points) p.latLng];
    if (pts.isEmpty) return;
    if (pts.length < 2) {
      try {
        _mapController.move(pts.first, 14);
        kickMapTileLayer(_mapController);
      } catch (_) {}
      return;
    }
    try {
      fitMapToBounds(
        _mapController,
        bounds: LatLngBounds.fromPoints(pts),
        padding: const EdgeInsets.all(28),
      );
    } catch (_) {}
  }

  void _openFullscreen() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DayTrackMapPage(
          days: widget.days,
          initialIndex: _index,
          mapStyle: _mapStyle,
          onDayChanged: (d) {
            final i =
                widget.days.indexWhere((x) => x.dayNumber == d.dayNumber);
            if (i >= 0 && i != _index) {
              setState(() => _index = i);
            }
            widget.onDayChanged?.call(d);
          },
        ),
      ),
    ).then((_) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fitDay();
        });
      }
    });
  }

  Widget _buildMiniMap(
    BuildContext context,
    AppLocalizations l10n,
    DayStats day,
  ) {
    final theme = Theme.of(context);
    final raw = [for (final p in day.points) p.latLng];
    final line = latLngsForMapDisplay(raw);
    final center = dayLabelAnchor(day);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _openFullscreen,
        child: SizedBox(
          height: 180,
          child: Stack(
            fit: StackFit.expand,
            children: [
              IgnorePointer(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter:
                        center.latitude == 0 && center.longitude == 0
                            ? const LatLng(39, 35)
                            : center,
                    initialZoom: 11,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                    backgroundColor: const Color(0xFFE8EEF2),
                    onMapReady: _fitDay,
                  ),
                  children: [
                    TileLayer(
                      key: ValueKey(_mapStyle.id),
                      urlTemplate: _mapStyle.urlTemplate,
                      subdomains: _mapStyle.subdomains,
                      tileProvider: createRideAtlasTileProvider(),
                      maxNativeZoom: _mapStyle.maxNativeZoom,
                      evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
                    ),
                    if (line.length >= 2)
                      PolylineLayer(
                        simplificationTolerance: 0.4,
                        polylines: [
                          Polyline(
                            points: line,
                            strokeWidth: 4,
                            color: day.color,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.fullscreen,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        l10n.dayDetailTapMapFullscreen,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;
    final dateFmt = DateFormat('d MMMM yyyy, EEEE', locale);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final day = _day;
    final showNote = widget.onAddNote != null && _index == _openedWithNoteIndex;
    final multi = widget.days.length > 1;
    final layout = context.watch<DayDetailStatsLayoutController>();

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Close top-left; export this day top-right (revise stays below).
              Row(
                children: [
                  IconButton(
                    tooltip:
                        MaterialLocalizations.of(context).closeButtonTooltip,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: l10n.dayDetailStatsLayoutTitle,
                    onPressed: () => _showDayDetailStatsLayoutSheet(context),
                    icon: const Icon(Icons.tune),
                  ),
                  if (widget.onExportDay != null)
                    IconButton(
                      tooltip: l10n.dayExportThisDayTooltip,
                      onPressed: _exporting ? null : _runExport,
                      icon: _exporting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.ios_share),
                    ),
                ],
              ),
              Row(
                children: [
                  if (multi)
                    IconButton(
                      tooltip: l10n.dayDetailPreviousDay,
                      onPressed: _canPrev ? () => _go(-1) : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: day.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${l10n.dayLabel(day.dayNumber)} · ${dateFmt.format(day.date)}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (multi)
                    IconButton(
                      tooltip: l10n.dayDetailNextDay,
                      onPressed: _canNext ? () => _go(1) : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                ],
              ),
              if (multi)
                Text(
                  '${_index + 1} / ${widget.days.length}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                l10n.dayDetailSubtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              _buildMiniMap(context, l10n, day),
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              _dayStatGrid(context: context, day: day, layout: layout),
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
              if (showNote ||
                  widget.onReviseDay != null ||
                  widget.onShowOnlyThisDay != null ||
                  widget.onShowAllDays != null) ...[
                const SizedBox(height: 12),
                if (showNote)
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onAddNote!();
                    },
                    icon: const Icon(Icons.add_location_alt),
                    label: Text(l10n.dayDetailAddNote),
                  ),
                if (widget.onReviseDay != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _revising ? null : _runRevise,
                    icon: const Icon(Icons.upload_file),
                    label: Text(l10n.dayDetailReviseButton),
                  ),
                ],
                if (widget.onShowOnlyThisDay != null) ...[
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onShowOnlyThisDay!(day);
                    },
                    child: Text(l10n.dayDetailShowOnlyThisDay),
                  ),
                ],
                if (widget.onShowAllDays != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onShowAllDays!();
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

/// Full-screen day track: map fills the screen; day stats sit as an overlay.
class DayTrackMapPage extends StatefulWidget {
  const DayTrackMapPage({
    super.key,
    required this.days,
    required this.initialIndex,
    required this.mapStyle,
    this.onDayChanged,
  });

  final List<DayStats> days;
  final int initialIndex;
  final BaseMapStyle mapStyle;
  final ValueChanged<DayStats>? onDayChanged;

  @override
  State<DayTrackMapPage> createState() => _DayTrackMapPageState();
}

class _DayTrackMapPageState extends State<DayTrackMapPage> {
  late int _index;
  final _mapController = MapController();

  DayStats get _day => widget.days[_index];
  bool get _canPrev => _index > 0;
  bool get _canNext => _index < widget.days.length - 1;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.days.length - 1);
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= widget.days.length) return;
    setState(() => _index = next);
    widget.onDayChanged?.call(_day);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitDay();
    });
  }

  void _fitDay() {
    final pts = [for (final p in _day.points) p.latLng];
    if (pts.isEmpty) return;
    if (pts.length < 2) {
      try {
        _mapController.move(pts.first, 14);
        kickMapTileLayer(_mapController);
      } catch (_) {}
      return;
    }
    try {
      fitMapToBounds(
        _mapController,
        bounds: LatLngBounds.fromPoints(pts),
        padding: const EdgeInsets.fromLTRB(40, 140, 40, 160),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;
    final dateFmt = DateFormat('d MMM yyyy', locale);
    final day = _day;
    final raw = [for (final p in day.points) p.latLng];
    final line = latLngsForMapDisplay(raw);
    final center = dayLabelAnchor(day);
    final multi = widget.days.length > 1;
    final layout = context.watch<DayDetailStatsLayoutController>();

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center.latitude == 0 && center.longitude == 0
                  ? const LatLng(39, 35)
                  : center,
              initialZoom: 11,
              backgroundColor: const Color(0xFFE8EEF2),
              onMapReady: _fitDay,
            ),
            children: [
              TileLayer(
                key: ValueKey(widget.mapStyle.id),
                urlTemplate: widget.mapStyle.urlTemplate,
                subdomains: widget.mapStyle.subdomains,
                tileProvider: createRideAtlasTileProvider(),
                maxNativeZoom: widget.mapStyle.maxNativeZoom,
                evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
              ),
              if (line.length >= 2)
                PolylineLayer(
                  simplificationTolerance: 0.4,
                  polylines: [
                    Polyline(
                      points: line,
                      strokeWidth: 5,
                      color: day.color,
                    ),
                  ],
                ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Material(
                      color: theme.colorScheme.surface.withValues(alpha: 0.92),
                      shape: const CircleBorder(),
                      elevation: 2,
                      child: IconButton(
                        tooltip: MaterialLocalizations.of(context)
                            .closeButtonTooltip,
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (multi)
                        Material(
                          color:
                              theme.colorScheme.surface.withValues(alpha: 0.92),
                          shape: const CircleBorder(),
                          elevation: 2,
                          child: IconButton(
                            tooltip: l10n.dayDetailPreviousDay,
                            onPressed: _canPrev ? () => _go(-1) : null,
                            icon: const Icon(Icons.chevron_left),
                          ),
                        ),
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface
                                .withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 6),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${l10n.dayLabel(day.dayNumber)} · ${dateFmt.format(day.date)}',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${day.distanceKm.toStringAsFixed(1)} km',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: day.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (multi)
                        Material(
                          color:
                              theme.colorScheme.surface.withValues(alpha: 0.92),
                          shape: const CircleBorder(),
                          elevation: 2,
                          child: IconButton(
                            tooltip: l10n.dayDetailNextDay,
                            onPressed: _canNext ? () => _go(1) : null,
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12 + MediaQuery.paddingOf(context).bottom,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(16),
              color: theme.colorScheme.surface.withValues(alpha: 0.94),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: l10n.dayDetailStatsLayoutTitle,
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            _showDayDetailStatsLayoutSheet(context),
                        icon: const Icon(Icons.tune, size: 20),
                      ),
                    ),
                    _dayStatGrid(
                      context: context,
                      day: day,
                      layout: layout,
                      compact: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DraggableDayStatTile extends StatelessWidget {
  const _DraggableDayStatTile({
    required this.statKey,
    required this.value,
    required this.layout,
    required this.accent,
    this.compact = false,
  });

  final DayDetailStatKey statKey;
  final String value;
  final DayDetailStatsLayoutController layout;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tile = _DayStatTile(
      icon: dayDetailStatIcon(statKey),
      label: dayDetailStatLabel(statKey, l10n),
      value: value,
      compact: compact,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        return LongPressDraggable<DayDetailStatKey>(
          data: statKey,
          delay: const Duration(milliseconds: 350),
          feedback: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: Material(
              color: Colors.transparent,
              child: Opacity(opacity: 0.92, child: tile),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.25, child: tile),
          child: DragTarget<DayDetailStatKey>(
            onWillAcceptWithDetails: (details) => details.data != statKey,
            onAcceptWithDetails: (details) =>
                unawaited(layout.swap(details.data, statKey)),
            builder: (context, candidateData, rejectedData) {
              if (candidateData.isEmpty) return tile;
              return DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent, width: 2),
                ),
                child: tile,
              );
            },
          ),
        );
      },
    );
  }
}

class _DayStatTile extends StatelessWidget {
  const _DayStatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: compact ? 18 : 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: (compact
                          ? theme.textTheme.titleSmall
                          : theme.textTheme.titleSmall)
                      ?.copyWith(fontWeight: FontWeight.w700),
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
