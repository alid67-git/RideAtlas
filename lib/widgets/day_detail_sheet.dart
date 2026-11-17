import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/base_map_style.dart';
import '../services/daily_analysis.dart';
import '../services/map_camera_fit.dart';
import '../services/track_display_simplify.dart';

const _metaBoxName = 'rideatlas_meta';
const _mapStyleKey = 'base_map_style_id';

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

List<({IconData icon, String label, String value})> _dayStatRows(
  AppLocalizations l10n,
  DayStats day,
) {
  return [
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
    ),
  );
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
  });

  final List<DayStats> days;
  final int initialIndex;
  final ValueChanged<DayStats>? onShowOnlyThisDay;
  final VoidCallback? onShowAllDays;
  final VoidCallback? onAddNote;
  final ValueChanged<DayStats>? onDayChanged;

  @override
  State<DayDetailSheet> createState() => _DayDetailSheetState();
}

class _DayDetailSheetState extends State<DayDetailSheet> {
  late int _index;
  BaseMapStyle _mapStyle = kBaseMapStyles.first;
  final _mapController = MapController();
  int _openedWithNoteIndex = -1;

  DayStats get _day => widget.days[_index];

  bool get _canPrev => _index > 0;
  bool get _canNext => _index < widget.days.length - 1;

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
    final stats = _dayStatRows(l10n, day);
    final showNote = widget.onAddNote != null && _index == _openedWithNoteIndex;
    final multi = widget.days.length > 1;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                  Expanded(
                    child: Row(
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
              if (showNote ||
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
    final stats = _dayStatRows(l10n, day);
    final multi = widget.days.length > 1;

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
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < stats.length; i += 2)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: i + 2 < stats.length ? 8 : 0,
                        ),
                        child: Row(
                          children: [
                            Expanded(child: _StatTile(stat: stats[i])),
                            const SizedBox(width: 8),
                            Expanded(
                              child: i + 1 < stats.length
                                  ? _StatTile(stat: stats[i + 1])
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
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
