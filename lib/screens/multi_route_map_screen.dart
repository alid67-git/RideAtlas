import 'dart:async';
import 'dart:math' show max, min, pi;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/base_map_style.dart';
import '../models/gpx_route.dart';
import '../models/track_point.dart';
import '../repositories/route_repository.dart';
import '../services/daily_analysis.dart' show colorForDay;
import '../services/track_io.dart';
import 'map_screen.dart' show MapStylePickerDialog;

const _metaBoxName = 'rideatlas_meta';
const _mapStyleKey = 'base_map_style_id';

/// Overlays several routes on one map, each drawn in its own color, with a
/// small legend that also re-centers the camera on a route when tapped.
///
/// Opens immediately on cached bounds (tiles + chrome), then parses each
/// GPX off the UI isolate and reveals polylines in batches - same idea as
/// single-route [RouteMapScreen], so picking ~20 long tracks never ANRs.
class MultiRouteMapScreen extends StatefulWidget {
  const MultiRouteMapScreen({super.key, required this.routeIds});

  final List<String> routeIds;

  @override
  State<MultiRouteMapScreen> createState() => _MultiRouteMapScreenState();
}

class _RouteLine {
  _RouteLine({
    required this.route,
    required this.points,
    required this.color,
  });

  final GpxRoute route;
  List<LatLng> points;
  final Color color;
}

class _MultiRouteMapScreenState extends State<MultiRouteMapScreen> {
  final _mapController = MapController();
  final List<_RouteLine> _lines = [];
  String? _error;
  BaseMapStyle _mapStyle = kBaseMapStyles.first;
  bool _bootstrapped = false;
  bool _loading = true;
  int _loadedCount = 0;
  Timer? _revealTimer;
  late List<String> _activeRouteIds;
  int _loadGeneration = 0;

  /// Compass bearing only - avoid [setState] on every rotate tick so long
  /// overlays are not rebuilt while the rider pinches/pans.
  final _rotationDeg = ValueNotifier<double>(0);
  late final StreamSubscription<MapEvent> _mapEventSub;

  @override
  void initState() {
    super.initState();
    _activeRouteIds = List<String>.from(widget.routeIds);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _loadMapStyle();
    _mapEventSub = _mapController.mapEventStream.listen((event) {
      final rotation = event.camera.rotation;
      if (rotation != _rotationDeg.value) {
        _rotationDeg.value = rotation;
      }
    });
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _mapEventSub.cancel();
    _rotationDeg.dispose();
    super.dispose();
  }

  void _resetNorth() => _mapController.rotate(0);

  Future<void> _loadMapStyle() async {
    final box = await Hive.openBox<String>(_metaBoxName);
    final savedId = box.get(_mapStyleKey);
    if (savedId == null || !mounted) return;
    setState(() => _mapStyle = findBaseMapStyle(savedId));
  }

  Future<void> _changeMapStyle(BaseMapStyle style) async {
    setState(() => _mapStyle = style);
    final box = await Hive.openBox<String>(_metaBoxName);
    await box.put(_mapStyleKey, style.id);
  }

  Future<void> _load() async {
    final gen = ++_loadGeneration;
    _revealTimer?.cancel();

    final repo = context.read<RouteRepository>();
    final byId = {for (final r in repo.routes) r.id: r};
    final routes = [
      for (final id in _activeRouteIds)
        if (byId[id] != null) byId[id]!,
    ];

    if (routes.isEmpty) {
      if (!mounted || gen != _loadGeneration) return;
      setState(() {
        _bootstrapped = true;
        _loading = false;
        _loadedCount = 0;
        _error = null;
        _lines.clear();
      });
      return;
    }

    // Tiles + camera first (metadata bounds only) - never wait on XML.
    setState(() {
      _bootstrapped = true;
      _loading = true;
      _loadedCount = 0;
      _error = null;
      _lines.clear();
    });
    _fitToRoutes(routes);

    try {
      for (var i = 0; i < routes.length; i++) {
        if (!mounted || gen != _loadGeneration) return;
        final route = routes[i];
        final xml = await repo.readTrackContent(route);
        if (!mounted || gen != _loadGeneration) return;
        final parsed = await compute(parseAndFilterTrackXml, xml);
        if (!mounted || gen != _loadGeneration) return;
        await _revealRoute(route, parsed.points, colorForDay(i), gen);
        if (!mounted || gen != _loadGeneration) return;
        setState(() => _loadedCount = i + 1);
      }
      if (!mounted || gen != _loadGeneration) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted || gen != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = AppLocalizations.of(context)!.routeFileReadError('$e');
      });
    }
  }

  /// Same picker as the recording overlay: Hepsi + checkboxes, then Göster
  /// reloads the map with the new selection (progressive draw again).
  Future<void> _reselectRoutes() async {
    final l10n = AppLocalizations.of(context)!;
    final routes = context.read<RouteRepository>().routes;
    if (routes.isEmpty) return;

    final selected = Set<String>.from(_activeRouteIds);
    final confirmed = await showDialog<bool>(
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
                      subtitle: Text(
                        '${route.distanceKm.toStringAsFixed(1)} km',
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(l10n.recordOverlayShow),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true || !mounted) return;

    final next = [
      for (final r in routes)
        if (selected.contains(r.id)) r.id,
    ];
    final same = next.length == _activeRouteIds.length &&
        next.asMap().entries.every((e) => e.value == _activeRouteIds[e.key]);
    if (same) return;

    setState(() => _activeRouteIds = next);
    await _load();
  }

  Future<void> _revealRoute(
    GpxRoute route,
    List<TrackPoint> trackPoints,
    Color color,
    int gen,
  ) async {
    final points = [for (final p in trackPoints) p.latLng];
    if (points.length < 2) return;
    if (!mounted || gen != _loadGeneration) return;

    final line = _RouteLine(route: route, points: const [], color: color);
    setState(() => _lines.add(line));
    final slot = _lines.length - 1;

    if (points.length < 150) {
      setState(() => _lines[slot].points = points);
      return;
    }

    final total = points.length;
    // Larger batches when many routes are queued so drawing finishes sooner.
    final routeFactor = max(1, _activeRouteIds.length ~/ 4);
    final batch = max(30, min(1200, (total / 60).ceil() * routeFactor));
    final done = Completer<void>();
    var shown = 0;

    _revealTimer?.cancel();
    _revealTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted || gen != _loadGeneration) {
        timer.cancel();
        if (!done.isCompleted) done.complete();
        return;
      }
      shown = min(total, shown + batch);
      setState(() => _lines[slot].points = points.sublist(0, shown));
      if (shown >= total) {
        timer.cancel();
        if (!done.isCompleted) done.complete();
      }
    });
    await done.future;
  }

  LatLngBounds _boundsFor(GpxRoute route) => LatLngBounds(
    LatLng(route.south, route.west),
    LatLng(route.north, route.east),
  );

  void _fitToRoutes(List<GpxRoute> routes) {
    if (routes.isEmpty) return;
    final bounds = _boundsFor(routes.first);
    for (final route in routes.skip(1)) {
      bounds.extendBounds(_boundsFor(route));
    }
    _fitBounds(bounds);
  }

  void _fitToAll(List<_RouteLine> lines) {
    if (lines.isEmpty) return;
    _fitToRoutes([for (final line in lines) line.route]);
  }

  void _fitBounds(LatLngBounds bounds) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
      );
    });
  }

  void _zoomIn() {
    final camera = _mapController.camera;
    _mapController.move(camera.center, camera.zoom + 1);
  }

  void _zoomOut() {
    final camera = _mapController.camera;
    _mapController.move(camera.center, camera.zoom - 1);
  }

  void _showMapStylePicker() {
    showDialog<void>(
      context: context,
      builder: (_) => MapStylePickerDialog(
        current: _mapStyle,
        onSelected: _changeMapStyle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final lines = _lines;
    final total = _activeRouteIds.length;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _buildMap()),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _RoundIconButton(
                          icon: Icons.arrow_back,
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Material(
                            color: Theme.of(
                              context,
                            ).colorScheme.surface.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(20),
                            elevation: 2,
                            shadowColor: Colors.black26,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: _reselectRoutes,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        l10n.routesCountLabel(total),
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.arrow_drop_down,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_loading && _bootstrapped) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: total > 0 ? _loadedCount / total : null,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (lines.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: _Legend(
                lines: List<_RouteLine>.from(lines),
                onTapLine: _fitBounds,
                boundsFor: _boundsFor,
              ),
            ),
          Positioned(
            right: 16,
            bottom: lines.isNotEmpty ? 96 : 24,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'multiMapStyle',
                  onPressed: _showMapStylePicker,
                  child: Icon(_mapStyle.icon),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'multiZoomIn',
                  onPressed: _zoomIn,
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'multiZoomOut',
                  onPressed: _zoomOut,
                  child: const Icon(Icons.remove),
                ),
                ValueListenableBuilder<double>(
                  valueListenable: _rotationDeg,
                  builder: (context, rotationDeg, _) {
                    if (rotationDeg.abs() <= 0.5) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: FloatingActionButton.small(
                        heroTag: 'multiNorthUp',
                        tooltip: l10n.northUpTooltip,
                        onPressed: _resetNorth,
                        child: Transform.rotate(
                          angle: -rotationDeg * pi / 180,
                          child: const Icon(Icons.navigation),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'multiFit',
                  onPressed: lines.isEmpty ? null : () => _fitToAll(lines),
                  child: const Icon(Icons.my_location),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    if (_error != null && !_bootstrapped) {
      return Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)),
      );
    }
    if (!_bootstrapped) {
      return const Center(child: CircularProgressIndicator());
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        // Camera is fitted to metadata bounds in [_load]; this is a fallback.
        initialCenter: const LatLng(39.0, 35.0),
        initialZoom: 5,
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
        if (_lines.isNotEmpty)
          PolylineLayer(
            polylines: [
              for (final line in _lines)
                if (line.points.length >= 2)
                  Polyline(
                    points: line.points,
                    strokeWidth: 4,
                    color: line.color,
                  ),
            ],
          ),
        RichAttributionWidget(
          attributions: [TextSourceAttribution(_mapStyle.attribution)],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.lines,
    required this.onTapLine,
    required this.boundsFor,
  });

  final List<_RouteLine> lines;
  final ValueChanged<LatLngBounds> onTapLine;
  final LatLngBounds Function(GpxRoute) boundsFor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: lines.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final line = lines[i];
          return ActionChip(
            backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.92),
            avatar: CircleAvatar(radius: 7, backgroundColor: line.color),
            label: Text(
              line.route.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: () => onTapLine(boundsFor(line.route)),
          );
        },
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      elevation: 2,
      child: IconButton(icon: Icon(icon), onPressed: onPressed),
    );
  }
}
