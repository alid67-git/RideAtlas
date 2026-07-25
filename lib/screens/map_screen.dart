import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/gpx_route.dart';
import '../models/track_point.dart';
import '../models/waypoint.dart';
import '../repositories/route_repository.dart';
import '../services/gpx_parser.dart';
import 'analysis_sheet.dart';

/// Shows a single imported GPX route on a map: the track as a red line,
/// green/red start & end pins, any named waypoints, and quick access to the
/// route list and detailed analysis - mirroring the reference screenshot's
/// layout (list button, title, share button, floating locate button).
class RouteMapScreen extends StatefulWidget {
  const RouteMapScreen({super.key, required this.routeId});

  final String routeId;

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  final _mapController = MapController();
  List<TrackPoint>? _points;
  List<Waypoint>? _waypoints;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  GpxRoute? get _route {
    final repo = context.read<RouteRepository>();
    try {
      return repo.routes.firstWhere((r) => r.id == widget.routeId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    final route = _route;
    if (route == null) return;
    try {
      final repo = context.read<RouteRepository>();
      final xml = await repo.readGpxContent(route);
      final parsed = parseGpxXml(xml);
      if (!mounted) return;
      setState(() {
        _points = parsed.points;
        _waypoints = parsed.waypoints;
      });
      _fitToRoute(route);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'GPX dosyası okunamadı: $e');
    }
  }

  void _fitToRoute(GpxRoute route) {
    final bounds = LatLngBounds(
      LatLng(route.south, route.west),
      LatLng(route.north, route.east),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
      );
    });
  }

  void _showList() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _openAnalysis(GpxRoute route) {
    final points = _points;
    if (points == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => AnalysisSheet(route: route, points: points),
    );
  }

  Future<void> _share(GpxRoute route) async {
    final repo = context.read<RouteRepository>();
    final xml = await repo.readGpxContent(route);
    final bytes = Uint8List.fromList(utf8.encode(xml));
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: '${route.name}.gpx', mimeType: 'application/gpx+xml')],
        subject: route.name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RouteRepository>(
      builder: (context, repo, _) {
        final route = _route;
        if (route == null) {
          return const Scaffold(body: Center(child: Text('Rota bulunamadı.')));
        }

        return Scaffold(
          body: Stack(
            children: [
              Positioned.fill(child: _buildMap(route)),
              _buildTopBar(context, route),
              Positioned(
                right: 16,
                bottom: 24,
                child: Column(
                  children: [
                    FloatingActionButton(
                      heroTag: 'locate',
                      onPressed: () => _fitToRoute(route),
                      child: const Icon(Icons.my_location),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton.extended(
                      heroTag: 'analysis',
                      onPressed: _points == null ? null : () => _openAnalysis(route),
                      icon: const Icon(Icons.insights),
                      label: const Text('Analiz'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMap(GpxRoute route) {
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)));
    }
    final points = _points;
    if (points == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final line = points.map((p) => p.latLng).toList();
    final start = line.first;
    final end = line.last;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: start,
        initialZoom: 12,
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds(LatLng(route.south, route.west), LatLng(route.north, route.east)),
          padding: const EdgeInsets.all(48),
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.rideatlas.app',
        ),
        PolylineLayer(
          polylines: [
            Polyline(points: line, strokeWidth: 4, color: const Color(0xFFE53935)),
          ],
        ),
        MarkerLayer(
          markers: [
            for (final w in _waypoints ?? const <Waypoint>[])
              Marker(
                point: w.latLng,
                width: 32,
                height: 32,
                child: Tooltip(
                  message: w.name ?? '',
                  child: const Icon(Icons.park, color: Colors.green, size: 28),
                ),
              ),
            Marker(
              point: start,
              width: 36,
              height: 36,
              child: const Icon(Icons.trip_origin, color: Color(0xFF2E7D32), size: 32),
            ),
            Marker(
              point: end,
              width: 36,
              height: 36,
              child: const Icon(Icons.location_on, color: Color(0xFFD32F2F), size: 36),
            ),
          ],
        ),
        const RichAttributionWidget(
          attributions: [TextSourceAttribution('OpenStreetMap katkıda bulunanlar')],
        ),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context, GpxRoute route) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            _RoundIconButton(icon: Icons.list, onPressed: _showList),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                ),
                child: Text(
                  route.name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _RoundIconButton(icon: Icons.ios_share, onPressed: () => _share(route)),
          ],
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

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
