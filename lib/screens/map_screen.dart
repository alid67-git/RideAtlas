import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/base_map_style.dart';
import '../models/gpx_route.dart';
import '../models/track_point.dart';
import '../models/waypoint.dart';
import '../repositories/route_repository.dart';
import '../services/daily_analysis.dart';
import '../services/track_io.dart';
import 'analysis_sheet.dart';

String _mapStyleLabel(AppLocalizations l10n, BaseMapStyle style) {
  return switch (style.id) {
    'voyager' => l10n.mapStyleVoyager,
    'positron' => l10n.mapStylePositron,
    'dark' => l10n.mapStyleDark,
    'satellite' => l10n.mapStyleSatellite,
    'topo' => l10n.mapStyleTopo,
    _ => style.label,
  };
}

const _metaBoxName = 'rideatlas_meta';
const _mapStyleKey = 'base_map_style_id';

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

  void _showMapStylePicker() {
    showDialog<void>(
      context: context,
      builder: (_) => _MapStylePickerDialog(
        current: _mapStyle,
        onSelected: _changeMapStyle,
      ),
    );
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
      final xml = await repo.readTrackContent(route);
      final parsed = parseTrackXml(xml);
      if (!mounted) return;
      setState(() {
        _points = parsed.points;
        _waypoints = parsed.waypoints;
      });
      _fitToRoute(route);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = AppLocalizations.of(context)!.routeFileReadError('$e'),
      );
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
      // On Flutter Web, TileLayer sometimes doesn't request tiles for the
      // very first programmatic camera move - a second, distinct move right
      // after reliably kicks it, without visibly changing the view.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final camera = _mapController.camera;
        _mapController.move(camera.center, camera.zoom + 0.001);
        _mapController.move(camera.center, camera.zoom);
      });
    });
  }

  void _showList(GpxRoute currentRoute) {
    showDialog<void>(
      context: context,
      builder: (_) => _RouteSwitcherDialog(currentRouteId: currentRoute.id),
    );
  }

  void _zoomIn() {
    final camera = _mapController.camera;
    _mapController.move(camera.center, camera.zoom + 1);
  }

  void _zoomOut() {
    final camera = _mapController.camera;
    _mapController.move(camera.center, camera.zoom - 1);
  }

  void _openAnalysis(GpxRoute route) {
    final points = _points;
    if (points == null) return;
    showDialog<void>(
      context: context,
      builder: (_) => AnalysisSheet(route: route, points: points),
    );
  }

  Future<void> _share(GpxRoute route) async {
    final points = _points;
    if (points == null) return;

    final format = await showDialog<TrackFormat>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(AppLocalizations.of(context)!.exportFormatQuestion),
        children: [
          for (final f in TrackFormat.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, f),
              child: Text(f.label),
            ),
        ],
      ),
    );
    if (format == null || !mounted) return;

    final export = buildTrackExport(
      name: route.name,
      points: points,
      waypoints: _waypoints ?? const [],
      format: format,
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            export.bytes,
            name: '${route.name}.${export.extension}',
            mimeType: export.mimeType,
          ),
        ],
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
          return Scaffold(
            body: Center(
              child: Text(AppLocalizations.of(context)!.routeNotFound),
            ),
          );
        }

        return Scaffold(
          body: Stack(
            children: [
              Positioned.fill(child: _buildMap(route)),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildTopBar(context, route),
              ),
              Positioned(
                right: 16,
                bottom: 24,
                child: Column(
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'mapStyle',
                      onPressed: _showMapStylePicker,
                      child: Icon(_mapStyle.icon),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      heroTag: 'zoomIn',
                      onPressed: _zoomIn,
                      child: const Icon(Icons.add),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      heroTag: 'zoomOut',
                      onPressed: _zoomOut,
                      child: const Icon(Icons.remove),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton(
                      heroTag: 'locate',
                      onPressed: () => _fitToRoute(route),
                      child: const Icon(Icons.my_location),
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
      return Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)),
      );
    }
    final points = _points;
    if (points == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final line = points.map((p) => p.latLng).toList();
    final start = line.first;
    final end = line.last;

    final days = splitIntoDays(points);
    final polylines = <Polyline>[
      if (days.isEmpty)
        Polyline(points: line, strokeWidth: 4, color: const Color(0xFFE53935))
      else
        for (var i = 0; i < days.length; i++)
          Polyline(
            points: [
              if (i > 0) days[i - 1].points.last.latLng,
              ...days[i].points.map((p) => p.latLng),
            ],
            strokeWidth: 4,
            color: days[i].color,
          ),
    ];

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(initialCenter: start, initialZoom: 12),
      children: [
        TileLayer(
          urlTemplate: _mapStyle.urlTemplate,
          subdomains: _mapStyle.subdomains,
          userAgentPackageName: 'com.rideatlas.app',
          maxNativeZoom: 20,
        ),
        PolylineLayer(polylines: polylines),
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
              child: const Icon(
                Icons.trip_origin,
                color: Color(0xFF2E7D32),
                size: 32,
              ),
            ),
            Marker(
              point: end,
              width: 36,
              height: 36,
              child: const Icon(
                Icons.location_on,
                color: Color(0xFFD32F2F),
                size: 36,
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

  Widget _buildTopBar(BuildContext context, GpxRoute route) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            _RoundIconButton(
              icon: Icons.list,
              onPressed: () => _showList(route),
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
                  route.name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _RoundIconButton(
              icon: Icons.insights,
              onPressed: _points == null ? null : () => _openAnalysis(route),
            ),
            const SizedBox(width: 8),
            _RoundIconButton(
              icon: Icons.ios_share,
              onPressed: () => _share(route),
            ),
          ],
        ),
      ),
    );
  }
}

/// Centered picker for the map's base tile style (street, satellite, etc.),
/// opened from the small layers button on the map screen.
class _MapStylePickerDialog extends StatelessWidget {
  const _MapStylePickerDialog({
    required this.current,
    required this.onSelected,
  });

  final BaseMapStyle current;
  final ValueChanged<BaseMapStyle> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.mapStyleTitle,
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: l10n.close,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: kBaseMapStyles.length,
                  itemBuilder: (context, i) {
                    final style = kBaseMapStyles[i];
                    final selected = style.id == current.id;
                    return ListTile(
                      leading: Icon(
                        style.icon,
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                      title: Text(_mapStyleLabel(l10n, style)),
                      selected: selected,
                      trailing: selected
                          ? Icon(Icons.check, color: theme.colorScheme.primary)
                          : null,
                      onTap: () {
                        onSelected(style);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Centered "switch route" window opened from the map screen's list button.
/// The current map stays underneath; picking another route swaps to it,
/// while dismissing (X, tap outside, or Esc) returns to the same map.
class _RouteSwitcherDialog extends StatefulWidget {
  const _RouteSwitcherDialog({required this.currentRouteId});

  final String currentRouteId;

  @override
  State<_RouteSwitcherDialog> createState() => _RouteSwitcherDialogState();
}

class _RouteSwitcherDialogState extends State<_RouteSwitcherDialog> {
  bool _importing = false;

  Future<void> _importTrack() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['gpx', 'kml', 'kmz'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    if (!mounted) return;

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.fileNotReadable)),
      );
      return;
    }

    setState(() => _importing = true);
    try {
      final repo = context.read<RouteRepository>();
      final route = await repo.importFromBytes(
        bytes: bytes,
        suggestedFileName: file.name,
      );
      if (!mounted) return;
      final navigator = Navigator.of(context);
      navigator.pop();
      navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => RouteMapScreen(routeId: route.id)),
      );
    } on FormatException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.trackHasNoPoints),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.importFailedGeneric('$e'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final routes = context.watch<RouteRepository>().routes;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.routesDialogTitle,
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    icon: _importing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add),
                    tooltip: l10n.importTooltip,
                    onPressed: _importing ? null : _importTrack,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: l10n.close,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: routes.length,
                  itemBuilder: (context, i) {
                    final r = routes[i];
                    final selected = r.id == widget.currentRouteId;
                    return ListTile(
                      leading: Icon(
                        Icons.route,
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                      title: Text(
                        r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text('${r.distanceKm.toStringAsFixed(1)} km'),
                      selected: selected,
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'rename') _renameRoute(context, r);
                          if (value == 'delete') {
                            _deleteRoute(context, r, selected);
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'rename',
                            child: Text(l10n.rename),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(l10n.delete),
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        if (!selected) {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => RouteMapScreen(routeId: r.id),
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _renameRoute(BuildContext context, GpxRoute route) async {
  final l10n = AppLocalizations.of(context)!;
  final controller = TextEditingController(text: route.name);
  final newName = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.renameRouteTitle),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: Text(l10n.save),
        ),
      ],
    ),
  );
  if (newName != null && newName.isNotEmpty && context.mounted) {
    await context.read<RouteRepository>().rename(route.id, newName);
  }
}

Future<void> _deleteRoute(
  BuildContext context,
  GpxRoute route,
  bool isCurrentlyOpen,
) async {
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.deleteRouteTitle),
      content: Text(l10n.deleteRouteConfirm(route.name)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.delete),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  await context.read<RouteRepository>().delete(route.id);
  if (!context.mounted) return;

  if (isCurrentlyOpen) {
    // The map this dialog was opened over no longer has a route to show.
    Navigator.of(context).popUntil((r) => r.isFirst);
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
