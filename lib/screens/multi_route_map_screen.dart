import 'dart:async';
import 'dart:math' show max, min, pi;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/base_map_style.dart';
import '../models/gpx_route.dart';
import '../repositories/photo_repository.dart';
import '../repositories/route_repository.dart';
import '../services/daily_analysis.dart' show colorForDay;
import '../services/map_camera_fit.dart';
import '../services/track_display_loader.dart';
import '../services/track_display_simplify.dart';
import '../widgets/route_photo_strip.dart' show PhotoViewerDialog;
import '../widgets/route_picker_dialog.dart';
import 'map_screen.dart' show MapStylePickerDialog;

const _metaBoxName = 'rideatlas_meta';
const _mapStyleKey = 'base_map_style_id';
const _lastRouteIdsKey = 'multiroute_last_route_ids';
const _lastCameraKey = 'multiroute_last_camera';

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
  DateTime? _lastProgressUiAt;
  late List<String> _activeRouteIds;
  int _loadGeneration = 0;
  String? _labeledRouteId;
  String? _labeledRouteName;
  LatLng? _labeledRoutePoint;

  /// Compass bearing only - avoid [setState] on every rotate tick so long
  /// overlays are not rebuilt while the rider pinches/pans.
  final _rotationDeg = ValueNotifier<double>(0);
  late final StreamSubscription<MapEvent> _mapEventSub;

  /// Camera to resume with instead of re-fitting bounds, set only when this
  /// screen reopens with the exact same route selection it last closed
  /// with - so returning to the same tracks continues at the same zoom/pan
  /// instead of always re-framing them. Consumed once, on the first load.
  LatLng? _restoredCenter;
  double? _restoredZoom;
  bool _restoredCameraConsumed = false;

  @override
  void initState() {
    super.initState();
    _activeRouteIds = List<String>.from(widget.routeIds);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadRestoredCamera();
      if (!mounted) return;
      await _load();
    });
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
    _mapEventSub.cancel();
    _rotationDeg.dispose();
    unawaited(_persistLastShown());
    super.dispose();
  }

  Future<void> _loadRestoredCamera() async {
    final box = await Hive.openBox<String>(_metaBoxName);
    final savedIds = box.get(_lastRouteIdsKey)?.split(',').toSet();
    final savedCamera = box.get(_lastCameraKey);
    if (!mounted || savedIds == null || savedCamera == null) return;
    if (!setEquals(savedIds, widget.routeIds.toSet())) return;
    final parts = savedCamera.split(',');
    if (parts.length != 3) return;
    final lat = double.tryParse(parts[0]);
    final lng = double.tryParse(parts[1]);
    final zoom = double.tryParse(parts[2]);
    if (lat == null || lng == null || zoom == null) return;
    _restoredCenter = LatLng(lat, lng);
    _restoredZoom = zoom;
  }

  Future<void> _persistLastShown() async {
    if (_activeRouteIds.isEmpty) return;
    try {
      final box = await Hive.openBox<String>(_metaBoxName);
      final camera = _mapController.camera;
      await box.put(_lastRouteIdsKey, _activeRouteIds.join(','));
      await box.put(
        _lastCameraKey,
        '${camera.center.latitude},${camera.center.longitude},${camera.zoom}',
      );
    } catch (_) {
      // Best-effort - losing the last-viewed camera isn't worth surfacing.
    }
  }

  void _resetNorth() => _mapController.rotate(0);

  Future<void> _loadMapStyle() async {
    final box = await Hive.openBox<String>(_metaBoxName);
    final savedId = box.get(_mapStyleKey);
    if (savedId == null || !mounted) return;
    setState(() => _mapStyle = findBaseMapStyle(savedId));
    kickMapTileLayer(_mapController);
  }

  Future<void> _changeMapStyle(BaseMapStyle style) async {
    setState(() => _mapStyle = style);
    kickMapTileLayer(_mapController);
    final box = await Hive.openBox<String>(_metaBoxName);
    await box.put(_mapStyleKey, style.id);
  }

  Future<void> _load() async {
    final gen = ++_loadGeneration;

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
    if (!_restoredCameraConsumed && _restoredCenter != null) {
      _restoredCameraConsumed = true;
      _moveToCamera(_restoredCenter!, _restoredZoom!);
    } else {
      _fitToRoutes(routes);
    }

    try {
      final budget = mapDisplayBudget(routes.length);
      final loaded = await loadTracksForMapDisplay(
        repo: repo,
        routes: routes,
        maxPoints: budget.maxPoints,
        minSpacingMeters: budget.minSpacingMeters,
        isCancelled: () => !mounted || gen != _loadGeneration,
        onProgress: (done, total) {
          if (!mounted || gen != _loadGeneration) return;
          // Throttle UI: rebuilding FlutterMap on every track completion
          // froze Android while ~20 GPX files were still parsing.
          final now = DateTime.now();
          final last = _lastProgressUiAt;
          if (done < total &&
              last != null &&
              now.difference(last) < const Duration(milliseconds: 250)) {
            return;
          }
          _lastProgressUiAt = now;
          setState(() => _loadedCount = done);
        },
      );
      if (!mounted || gen != _loadGeneration) return;

      // Paint once after everything is in memory (cache or fresh parse).
      setState(() {
        _lines
          ..clear()
          ..addAll([
            for (final track in loaded)
              _RouteLine(
                route: track.route,
                points: track.points,
                color: colorForDay(track.index),
              ),
          ]);
        _loading = false;
        _loadedCount = routes.length;
      });
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
    final routes = context.read<RouteRepository>().routes;
    if (routes.isEmpty) return;

    final selected = await showRoutePickerDialog(
      context: context,
      routes: routes,
      initiallySelected: _activeRouteIds.toSet(),
    );
    if (selected == null || !mounted) return;

    var next = [
      for (final r in routes)
        if (selected.contains(r.id)) r.id,
    ];
    next = await _capRouteIds(next) ?? const <String>[];
    if (next.isEmpty || !mounted) return;
    final same = next.length == _activeRouteIds.length &&
        next.asMap().entries.every((e) => e.value == _activeRouteIds[e.key]);
    if (same) return;

    setState(() => _activeRouteIds = next);
    await _load();
  }

  /// Soft/hard caps shared with home/record "show all".
  Future<List<String>?> _capRouteIds(List<String> ids) async {
    final l10n = AppLocalizations.of(context)!;
    if (ids.length > kShowAllRoutesHardCap) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.showAllTracksTooManyTitle),
          content: Text(
            l10n.showAllTracksTooManyMessage(
              ids.length,
              kShowAllRoutesHardCap,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.showAllTracksLimitButton),
            ),
          ],
        ),
      );
      if (ok != true) return null;
      return ids.take(kShowAllRoutesHardCap).toList();
    }
    if (ids.length > kShowAllRoutesSoftCap) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.showAllTracksHeavyTitle),
          content: Text(l10n.showAllTracksHeavyMessage(ids.length)),
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
        ),
      );
      if (ok != true) return null;
    }
    return ids;
  }

  LatLngBounds _boundsFor(GpxRoute route) =>
      boundsForRoutes([route]) ??
      LatLngBounds(LatLng(route.south, route.west), LatLng(route.north, route.east));

  void _fitToRoutes(List<GpxRoute> routes) {
    final bounds = boundsForRoutes(routes);
    if (bounds == null) return;
    _fitBounds(bounds);
  }

  void _fitToAll(List<_RouteLine> lines) {
    if (lines.isEmpty) return;
    _fitToRoutes([for (final line in lines) line.route]);
  }

  void _fitBounds(LatLngBounds bounds) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      fitMapToBounds(_mapController, bounds: bounds);
    });
  }

  void _moveToCamera(LatLng center, double zoom) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.move(center, zoom);
      kickMapTileLayer(_mapController);
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
                  tooltip: l10n.fitRouteTooltip,
                  onPressed: lines.isEmpty ? null : () => _fitToAll(lines),
                  child: const Icon(Icons.zoom_out_map),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  void _onMapTap(TapPosition tapPosition, LatLng latlng) {
    final hit = findNearestTrackHit(
      tap: latlng,
      zoom: _mapController.camera.zoom,
      tracks: [
        for (final line in _lines)
          (id: line.route.id, name: line.route.name, points: line.points),
      ],
    );
    setState(() {
      if (hit == null || hit.id == _labeledRouteId) {
        _labeledRouteId = null;
        _labeledRouteName = null;
        _labeledRoutePoint = null;
      } else {
        _labeledRouteId = hit.id;
        _labeledRouteName = hit.name;
        _labeledRoutePoint = hit.point;
      }
    });
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
        onTap: _onMapTap,
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
            // 1.5 idi: virajlı yollarda köşeleri kesip yolu takip etmeyen
            // kaba bir çizgiye dönüştürüyordu.
            simplificationTolerance: 0.4,
            polylines: [
              for (final line in _lines)
                if (line.points.length >= 2)
                  Polyline(
                    points: line.points,
                    // Slightly thinner on multi-route maps: 20× strokeWidth 4
                    // overdraw was a big part of the Android show-all stall.
                    strokeWidth: 3,
                    color: line.color,
                  ),
            ],
          ),
        Builder(
          builder: (context) {
            // Lightweight pins only — PhotoThumb decoded full images for
            // every geotagged photo on every route and OOM'd show-all.
            // Skip entirely with many routes: even metadata scans stall Android.
            if (_lines.length > kMapPhotoPinRouteCap) {
              return const SizedBox.shrink();
            }
            final photos = context.read<PhotoRepository>();
            var remaining = kMapPhotoPinCap;
            final markers = <Marker>[];
            for (final line in _lines) {
              if (remaining <= 0) break;
              for (final photo
                  in photos.photosFor(line.route.id).where((p) => p.hasLocation)) {
                if (remaining <= 0) break;
                remaining--;
                final routeId = line.route.id;
                final photoId = photo.id;
                final isVideo = photo.isVideo;
                markers.add(
                  Marker(
                    point: photo.latLng!,
                    width: 28,
                    height: 28,
                    child: GestureDetector(
                      onTap: () {
                        showDialog<void>(
                          context: context,
                          builder: (_) => PhotoViewerDialog(
                            routeId: routeId,
                            initialPhotoId: photoId,
                          ),
                        );
                      },
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: isVideo
                              ? Colors.deepPurple
                              : Colors.teal,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [
                            BoxShadow(color: Colors.black38, blurRadius: 3),
                          ],
                        ),
                        child: Icon(
                          isVideo ? Icons.videocam : Icons.photo_camera,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                );
              }
            }
            if (markers.isEmpty) return const SizedBox.shrink();
            return MarkerLayer(markers: markers);
          },
        ),
        if (_labeledRoutePoint != null && _labeledRouteName != null)
          MarkerLayer(
            markers: [
              Marker(
                point: _labeledRoutePoint!,
                width: 180,
                height: 36,
                alignment: Alignment.bottomCenter,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      _labeledRouteName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
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
