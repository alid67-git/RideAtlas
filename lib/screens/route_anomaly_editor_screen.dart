import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/gpx_route.dart';
import '../models/parsed_track.dart';
import '../models/track_point.dart';
import '../models/waypoint.dart';
import '../repositories/route_repository.dart';
import '../services/gpx_parser.dart';
import '../services/track_io.dart';

/// Lets a rider review and permanently remove GPS glitch points (a fix that
/// implies an impossible speed jump from its neighbor - a single "sıçrama"
/// on the map) from an already-saved route. [filterImplausiblePoints] does
/// the same detection to silently clean up the map/stats display, but that
/// never touches the stored file - a rider who wants the glitch gone from
/// the route itself (e.g. before sharing it) needs this instead.
class RouteAnomalyEditorScreen extends StatefulWidget {
  const RouteAnomalyEditorScreen({super.key, required this.route});

  final GpxRoute route;

  @override
  State<RouteAnomalyEditorScreen> createState() =>
      _RouteAnomalyEditorScreenState();
}

class _RouteAnomalyEditorScreenState extends State<RouteAnomalyEditorScreen> {
  List<TrackPoint>? _points;
  List<Waypoint>? _waypoints;
  String? _error;
  bool _saving = false;

  /// Indices into [_points] the rider has chosen to remove - starts as
  /// every detected anomaly (opt-out, not opt-in: the whole point of this
  /// screen is "here's what looks wrong, uncheck anything you actually
  /// want to keep").
  final Set<int> _toDelete = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = context.read<RouteRepository>();
      final xml = await repo.readTrackContent(widget.route);
      final parsed = parseTrackXml(xml);
      if (!mounted) return;
      final flagged = findImplausiblePointIndices(parsed.points);
      setState(() {
        _points = parsed.points;
        _waypoints = parsed.waypoints;
        _toDelete
          ..clear()
          ..addAll(flagged);
      });
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = AppLocalizations.of(context)!.routeFileReadError('$e'),
      );
    }
  }

  double _impliedKmh(TrackPoint from, TrackPoint to) {
    final t0 = from.time;
    final t1 = to.time;
    if (t0 == null || t1 == null) return 0;
    final dtSeconds = t1.difference(t0).inMilliseconds / 1000.0;
    if (dtSeconds <= 0) return 0;
    final meters = const Distance()(from.latLng, to.latLng);
    return (meters / dtSeconds) * 3.6;
  }

  Future<void> _save() async {
    final points = _points;
    final waypoints = _waypoints;
    if (points == null || waypoints == null || _toDelete.isEmpty) return;
    setState(() => _saving = true);

    final cleaned = [
      for (var i = 0; i < points.length; i++)
        if (!_toDelete.contains(i)) points[i],
    ];
    final route = widget.route;
    final xml = exportTrack(
      name: route.name,
      points: cleaned,
      waypoints: waypoints,
      format: TrackFormat.gpx,
    );
    final metadata = buildRouteMetadata(
      id: route.id,
      name: route.name,
      importedAt: route.importedAt,
      parsed: ParsedTrack(
        points: cleaned,
        waypoints: waypoints,
        suggestedName: null,
      ),
      batteryStartPercent: route.batteryStartPercent,
      batteryEndPercent: route.batteryEndPercent,
    );
    await context.read<RouteRepository>().updateContent(
      id: route.id,
      xml: xml,
      metadata: metadata,
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final points = _points;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.anomalyEditorTitle),
        actions: [
          if (points != null && _toDelete.isNotEmpty)
            TextButton(
              onPressed: _saving ? null : _save,
              child: Text(l10n.save),
            ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : points == null
          ? const Center(child: CircularProgressIndicator())
          : _toDelete.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.anomalyEditorEmpty,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l10n.anomalyEditorFoundCount(_toDelete.length)),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _toDelete.length,
                    itemBuilder: (context, i) {
                      final index = _toDelete.elementAt(i);
                      final point = points[index];
                      final prev = index > 0 ? points[index - 1] : null;
                      final kmh = prev == null
                          ? 0.0
                          : _impliedKmh(prev, point);
                      return CheckboxListTile(
                        value: true,
                        onChanged: (_) =>
                            setState(() => _toDelete.remove(index)),
                        title: Text(
                          '${point.latLng.latitude.toStringAsFixed(5)}, '
                          '${point.latLng.longitude.toStringAsFixed(5)}',
                        ),
                        subtitle: Text(
                          l10n.anomalyEditorPointSpeed(kmh.round()),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
