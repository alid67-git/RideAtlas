import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/base_map_style.dart';
import '../models/gpx_route.dart';
import '../repositories/route_repository.dart';
import '../services/daily_analysis.dart' show colorForDay;
import '../services/track_io.dart';
import 'map_screen.dart' show MapStylePickerDialog;

const _metaBoxName = 'rideatlas_meta';
const _mapStyleKey = 'base_map_style_id';

/// Overlays several routes on one map, each drawn in its own color, with a
/// small legend that also re-centers the camera on a route when tapped.
class MultiRouteMapScreen extends StatefulWidget {
  const MultiRouteMapScreen({super.key, required this.routeIds});

  final List<String> routeIds;

  @override
  State<MultiRouteMapScreen> createState() => _MultiRouteMapScreenState();
}

class _RouteLine {
  const _RouteLine({
    required this.route,
    required this.points,
    required this.color,
  });

  final GpxRoute route;
  final List<LatLng> points;
  final Color color;
}

class _MultiRouteMapScreenState extends State<MultiRouteMapScreen> {
  final _mapController = MapController();
  List<_RouteLine>? _lines;
  String? _error;
  BaseMapStyle _mapStyle = kBaseMapStyles.first;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _loadMapStyle();
  }

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
    final repo = context.read<RouteRepository>();
    final byId = {for (final r in repo.routes) r.id: r};
    final routes = [
      for (final id in widget.routeIds)
        if (byId[id] != null) byId[id]!,
    ];

    try {
      final lines = <_RouteLine>[];
      for (var i = 0; i < routes.length; i++) {
        final route = routes[i];
        final xml = await repo.readTrackContent(route);
        final parsed = parseTrackXml(xml);
        lines.add(
          _RouteLine(
            route: route,
            points: [for (final p in parsed.points) p.latLng],
            color: colorForDay(i),
          ),
        );
      }
      if (!mounted) return;
      setState(() => _lines = lines);
      _fitToAll(lines);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = AppLocalizations.of(context)!.routeFileReadError('$e'),
      );
    }
  }

  LatLngBounds _boundsFor(GpxRoute route) => LatLngBounds(
    LatLng(route.south, route.west),
    LatLng(route.north, route.east),
  );

  void _fitToAll(List<_RouteLine> lines) {
    if (lines.isEmpty) return;
    final bounds = _boundsFor(lines.first.route);
    for (final line in lines.skip(1)) {
      bounds.extendBounds(_boundsFor(line.route));
    }
    _fitBounds(bounds);
  }

  void _fitBounds(LatLngBounds bounds) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
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

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _buildMap(lines)),
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
                child: Row(
                  children: [
                    _RoundIconButton(
                      icon: Icons.arrow_back,
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surface.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 6),
                          ],
                        ),
                        child: Text(
                          l10n.routesCountLabel(widget.routeIds.length),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (lines != null && lines.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: _Legend(lines: lines, onTapLine: _fitBounds, boundsFor: _boundsFor),
            ),
          Positioned(
            right: 16,
            bottom: lines != null && lines.isNotEmpty ? 96 : 24,
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
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'multiFit',
                  onPressed: lines == null ? null : () => _fitToAll(lines),
                  child: const Icon(Icons.my_location),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap(List<_RouteLine>? lines) {
    if (_error != null) {
      return Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)),
      );
    }
    if (lines == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: lines.isEmpty
            ? const LatLng(0, 0)
            : lines.first.points.first,
        initialZoom: 6,
      ),
      children: [
        TileLayer(
          urlTemplate: _mapStyle.urlTemplate,
          subdomains: _mapStyle.subdomains,
          userAgentPackageName: 'com.rideatlas.app',
          maxNativeZoom: 20,
        ),
        PolylineLayer(
          polylines: [
            for (final line in lines)
              Polyline(points: line.points, strokeWidth: 4, color: line.color),
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
