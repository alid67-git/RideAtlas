import 'dart:async';
import 'dart:io';
import 'dart:math' show max, min, pi;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:hive/hive.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/base_map_style.dart';
import '../models/gpx_route.dart';
import '../models/route_photo.dart';
import '../models/track_point.dart';
import '../models/waypoint.dart';
import '../repositories/photo_repository.dart';
import '../repositories/route_repository.dart';
import '../services/daily_analysis.dart';
import '../services/exif_gps.dart';
import '../services/map_camera_fit.dart';
import '../services/route_geography.dart';
import '../services/track_io.dart';
import '../widgets/recording_indicator.dart';
import '../widgets/route_photo_strip.dart';
import 'analysis_sheet.dart';
import 'location_picker_screen.dart';
import 'multi_route_map_screen.dart';
import 'route_anomaly_editor_screen.dart';
import 'settings_screen.dart';

/// Videos picked from the gallery come back as a plain [XFile] alongside
/// photos, with no separate list to tell them apart - this is how we sort
/// them back out.
bool _looksLikeVideo(XFile file) {
  final mime = file.mimeType;
  if (mime != null) return mime.startsWith('video/');
  final name = file.name.toLowerCase();
  return name.endsWith('.mp4') ||
      name.endsWith('.mov') ||
      name.endsWith('.m4v') ||
      name.endsWith('.avi') ||
      name.endsWith('.webm') ||
      name.endsWith('.3gp');
}

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

/// Where each calendar day's riding ends and the next begins - i.e. the
/// overnight stay. A GPS dwell-radius heuristic can miss overnights (the
/// arrival and departure points aren't always within the same few hundred
/// meters - parking, a different hotel entrance, etc.), but the calendar-day
/// boundary itself always exists once a route spans multiple days, so this
/// is used instead of guessing from stop duration.
typedef OvernightStay = ({LatLng location, Duration? duration});

List<OvernightStay> overnightStays(List<DayStats> days) {
  final out = <OvernightStay>[];
  for (var i = 0; i < days.length - 1; i++) {
    final end = days[i].points.last;
    final start = days[i + 1].points.first;
    final t0 = end.time;
    final t1 = start.time;
    out.add((
      location: end.latLng,
      duration: (t0 != null && t1 != null && t1.isAfter(t0))
          ? t1.difference(t0)
          : null,
    ));
  }
  return out;
}

const _trackRevealColor = Color(0xFFE53935);

/// Final map polylines after progressive reveal.
///
/// Day-colored segments are used only when they cover every track point.
/// [splitIntoDays] skips points with a null timestamp - if any points *do*
/// have times, a naïve rebuild would drop the untimed majority and the red
/// reveal line would appear to vanish. An empty day-filter match falls back
/// to the full track for the same reason.
List<Polyline> buildTrackPolylines({
  required List<TrackPoint> points,
  required List<DayStats> days,
  Set<int>? visibleDayNumbers,
}) {
  if (points.isEmpty) return const [];

  Polyline fullTrack({Color? color}) => Polyline(
        points: [for (final p in points) p.latLng],
        strokeWidth: 4,
        color: color ?? _trackRevealColor,
      );

  if (days.isEmpty) return [fullTrack()];

  final covered = days.fold<int>(0, (n, d) => n + d.points.length);
  if (covered < points.length) {
    // Partial timestamps: keep the full line the reveal already drew.
    return [fullTrack()];
  }

  bool isShown(int index) =>
      visibleDayNumbers == null ||
      visibleDayNumbers.contains(days[index].dayNumber);

  final built = <Polyline>[
    for (var i = 0; i < days.length; i++)
      if (isShown(i))
        Polyline(
          points: [
            // Only bridge into the previous day's last point when that
            // day is consecutive AND also visible - otherwise a gap
            // (e.g. day 1 + day 7 selected) would draw a stray line
            // straight across the skipped days.
            if (i > 0 && isShown(i - 1)) days[i - 1].points.last.latLng,
            for (final p in days[i].points) p.latLng,
          ],
          strokeWidth: 4,
          color: days[i].color,
        ),
  ];

  // Stale day filter (e.g. after reload) must never blank the map.
  return built.isNotEmpty ? built : [fullTrack()];
}

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

  /// Whether the map chrome (tiles + camera) is up - shown immediately from
  /// route bounds, before the GPX body has finished parsing.
  bool _mapBootstrapped = false;

  /// True while the track line is still being revealed (or parsed).
  bool _trackDrawing = false;

  Timer? _revealTimer;
  Completer<void>? _revealDone;

  /// Bumped on every [_load] so an overlapping reload (repo edit, rapid
  /// reopen) cannot finish a stale reveal/apply after [_bootstrapMap] has
  /// already cleared the polylines for a newer generation.
  int _loadGeneration = 0;

  /// Cached from [_points] once on load (and after a route edit reload).
  /// Recomputing [splitIntoDays] / [RouteGeographyAnalyzer.detectStops] on
  /// every [setState] - including map-gesture rotation ticks - was freezing
  /// the UI when panning/zooming a long imported track.
  List<DayStats> _days = const [];
  List<DetectedStop> _stops = const [];
  List<OvernightStay> _overnights = const [];
  List<Polyline> _polylines = const [];
  LatLng? _trackStart;
  LatLng? _trackEnd;

  /// The route metadata as of the last successful [_load] - compared
  /// against the repository's current copy on every change notification so
  /// an edit made elsewhere (e.g. removing anomalous points through the
  /// route anomaly editor) reloads this screen's points/map automatically,
  /// without reparsing on every unrelated repository change (a rename of a
  /// completely different route, say).
  GpxRoute? _loadedRouteSnapshot;

  /// Which day numbers to draw on the map. Null means "show every day" (the
  /// default); a non-null set is always non-empty, so the map never goes
  /// blank from the filter alone.
  Set<int>? _visibleDayNumbers;

  /// Whether detected-stop pins (rest stops and overnight stays) are drawn
  /// on the map. Off by default so a ride's first view is uncluttered; a
  /// button lets riders reveal them when they want the detail.
  bool _showStops = false;

  /// Whether geotagged photo/video pins are drawn on the map. On by default
  /// (unlike [_showStops]) since these are media the rider deliberately
  /// attached - worth surfacing without an extra tap; the button still lets
  /// them hide the clutter on a busy route.
  bool _showPhotoPins = true;

  /// Map bearing for the north-up compass only. A [ValueNotifier] (not
  /// [setState]) so pinch/rotate gestures do not rebuild the track polyline.
  final _rotationDeg = ValueNotifier<double>(0);
  late final StreamSubscription<MapEvent> _mapEventSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _loadMapStyle();
    _mapEventSub = _mapController.mapEventStream.listen((event) {
      final rotation = event.camera.rotation;
      if (rotation != _rotationDeg.value) {
        _rotationDeg.value = rotation;
      }
    });
    context.read<RouteRepository>().addListener(_onRepoChanged);
  }

  @override
  void dispose() {
    context.read<RouteRepository>().removeListener(_onRepoChanged);
    _cancelReveal();
    _mapEventSub.cancel();
    _rotationDeg.dispose();
    super.dispose();
  }

  void _cancelReveal() {
    _revealTimer?.cancel();
    _revealTimer = null;
    final done = _revealDone;
    if (done != null && !done.isCompleted) {
      done.complete();
    }
    _revealDone = null;
  }

  void _onRepoChanged() {
    final route = _route;
    final loaded = _loadedRouteSnapshot;
    if (route == null || loaded == null) return;
    if (route.distanceMeters != loaded.distanceMeters ||
        route.pointCount != loaded.pointCount) {
      _load();
    }
  }

  void _resetNorth() => _mapController.rotate(0);

  /// Centers on a detected stop, zooming in only if currently more zoomed
  /// out than that - tapping again once already close just re-centers.
  void _zoomToStop(LatLng point) {
    final zoom = _mapController.camera.zoom;
    _mapController.move(point, zoom < 15 ? 15 : zoom);
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
      builder: (_) =>
          MapStylePickerDialog(current: _mapStyle, onSelected: _changeMapStyle),
    );
  }

  void _showDayFilterPicker(List<DayStats> days) {
    showDialog<void>(
      context: context,
      builder: (_) => _DayFilterDialog(
        days: days,
        selected: _visibleDayNumbers,
        onChanged: (selected) => setState(() {
          _visibleDayNumbers = selected;
          _rebuildPolylines();
        }),
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

  /// Commits track geometry + day-colored polylines. Stop pins are filled in
  /// afterwards by [_loadStops] so a heavy [detectStops] pass cannot blank
  /// the line (or throw) during the reveal→final handoff.
  void _applyLoadedPoints(List<TrackPoint> points, List<Waypoint> waypoints) {
    final days = splitIntoDays(points);
    _points = points;
    _waypoints = waypoints;
    _days = days;
    _overnights = overnightStays(days);
    _trackStart = points.isEmpty ? null : points.first.latLng;
    _trackEnd = points.isEmpty ? null : points.last.latLng;
    _rebuildPolylines();
  }

  void _rebuildPolylines() {
    final points = _points;
    if (points == null || points.isEmpty) {
      _polylines = const [];
      return;
    }
    _polylines = buildTrackPolylines(
      points: points,
      days: _days,
      visibleDayNumbers: _visibleDayNumbers,
    );
  }

  Future<void> _loadStops(List<TrackPoint> points, int gen) async {
    // Yield so the reveal→final polyline frame can paint before stop
    // clustering runs on the UI isolate.
    await Future<void>.delayed(Duration.zero);
    if (!mounted || gen != _loadGeneration) return;
    final stops = RouteGeographyAnalyzer()
        .detectStops(points)
        .where((s) => s.duration < const Duration(hours: 4))
        .toList();
    if (!mounted || gen != _loadGeneration) return;
    setState(() => _stops = stops);
  }

  /// Shows tiles + camera fitted to the route's cached bounds immediately,
  /// before any GPX parsing - so tapping a long track never sits on a
  /// blank spinner while the isolate works.
  void _bootstrapMap(GpxRoute route) {
    final center = LatLng(
      (route.north + route.south) / 2,
      (route.east + route.west) / 2,
    );
    setState(() {
      _error = null;
      _mapBootstrapped = true;
      _trackDrawing = true;
      _points = null;
      _waypoints = null;
      _days = const [];
      _stops = const [];
      _overnights = const [];
      _polylines = const [];
      // Fresh load must not keep a prior day filter that can match nothing
      // after day renumbering and blank the final polylines.
      _visibleDayNumbers = null;
      _trackStart = center;
      _trackEnd = center;
    });
    _fitToRoute(route);
  }

  /// Grows the drawn polyline in batches so a long GPX appears to be "read"
  /// onto the map instead of popping in all at once after a long wait.
  Future<void> _revealTrack(List<TrackPoint> points, int gen) async {
    if (points.isEmpty) {
      if (!mounted || gen != _loadGeneration) return;
      setState(() {
        _polylines = const [];
        _trackStart = null;
        _trackEnd = null;
      });
      return;
    }

    // Short tracks: one frame is enough - animation would just flicker.
    if (points.length < 150) {
      if (!mounted || gen != _loadGeneration) return;
      setState(() {
        _trackStart = points.first.latLng;
        _trackEnd = points.last.latLng;
        _polylines = [
          Polyline(
            points: [for (final p in points) p.latLng],
            strokeWidth: 4,
            color: _trackRevealColor,
          ),
        ];
      });
      return;
    }

    final total = points.length;
    final batch = max(30, min(800, (total / 60).ceil()));
    final start = points.first.latLng;
    final done = Completer<void>();
    var shown = 0;

    _cancelReveal();
    _revealDone = done;
    _revealTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted || gen != _loadGeneration) {
        timer.cancel();
        if (!done.isCompleted) done.complete();
        return;
      }
      shown = min(total, shown + batch);
      final line = <LatLng>[
        for (var i = 0; i < shown; i++) points[i].latLng,
      ];
      setState(() {
        _trackStart = start;
        _trackEnd = line.last;
        _polylines = [
          Polyline(
            points: line,
            strokeWidth: 4,
            color: _trackRevealColor,
          ),
        ];
      });
      if (shown >= total) {
        timer.cancel();
        if (!done.isCompleted) done.complete();
      }
    });
    await done.future;
  }

  Future<void> _load() async {
    final route = _route;
    if (route == null) return;
    final gen = ++_loadGeneration;
    _cancelReveal();
    _bootstrapMap(route);

    try {
      final repo = context.read<RouteRepository>();
      final xml = await repo.readTrackContent(route);
      if (!mounted || gen != _loadGeneration) return;

      // Parse + GPS-glitch filter off the UI isolate so the map keeps
      // painting tiles while a multi-hour GPX is being read.
      final parsed = await compute(parseAndFilterTrackXml, xml);
      if (!mounted || gen != _loadGeneration) return;

      await _revealTrack(parsed.points, gen);
      if (!mounted || gen != _loadGeneration) return;

      setState(() {
        // Days derived once the full line is on screen - not before the
        // first paint (that was what made large files look "stuck").
        _applyLoadedPoints(parsed.points, parsed.waypoints);
        _trackDrawing = false;
      });
      _loadedRouteSnapshot = route;
      unawaited(_loadStops(parsed.points, gen));
    } catch (e) {
      if (!mounted || gen != _loadGeneration) return;
      setState(() {
        _trackDrawing = false;
        _error = AppLocalizations.of(context)!.routeFileReadError('$e');
      });
    }
  }

  void _fitToRoute(GpxRoute route) {
    final bounds = boundsForRoutes([route]);
    if (bounds == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      fitMapToBounds(_mapController, bounds: bounds);
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

    // Defaults to the route's own saved name - riders only need to type
    // something different when they actually want to (e.g. a merged
    // route's auto-generated "A + B" name), not on every single export.
    final nameController = TextEditingController(text: route.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.exportNameQuestion),
        content: TextField(controller: nameController, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, nameController.text.trim()),
            child: Text(AppLocalizations.of(context)!.save),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;

    final export = buildTrackExport(
      name: name,
      points: points,
      waypoints: _waypoints ?? const [],
      format: format,
    );
    XFile shareFile;
    if (kIsWeb) {
      // No filesystem to write a real file to - the browser's own
      // save/share affordance reads the name from XFile.fromData directly.
      shareFile = XFile.fromData(
        export.bytes,
        name: '$name.${export.extension}',
        mimeType: export.mimeType,
      );
    } else {
      // XFile.fromData doesn't reliably carry its `name:` through to the
      // share sheet on Android - the receiving app shows some internal
      // random-looking temp name instead of the one just chosen above. A
      // real file on disk, named up front, is what actually shows up in
      // the share sheet.
      final safeName = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$safeName.${export.extension}');
      await file.writeAsBytes(export.bytes);
      shareFile = XFile(file.path, mimeType: export.mimeType);
    }
    await SharePlus.instance.share(
      ShareParams(files: [shareFile], subject: name),
    );
  }

  /// A single entry point for adding either photos or videos: picking from
  /// the gallery uses one unified picker that returns a mix of both, no
  /// separate "photo" vs "video" menu needed. The camera is the one
  /// unavoidable exception - Android/iOS only offer separate photo-capture
  /// and video-capture intents, so that still needs one quick follow-up
  /// question, but it's the only place that does.
  Future<void> _addMedia(GpxRoute route) async {
    final l10n = AppLocalizations.of(context)!;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: Text(l10n.cameraSourceLabel),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(l10n.gallerySourceLabel),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    try {
      final picker = ImagePicker();
      if (source == ImageSource.camera) {
        final mediaType = await _pickCameraMediaType();
        if (mediaType == null || !mounted) return;
        if (mediaType == RouteMediaType.video) {
          final file = await picker.pickVideo(source: ImageSource.camera);
          if (file != null) await _saveVideo(route, file);
        } else {
          final file = await picker.pickImage(
            source: ImageSource.camera,
            imageQuality: 85,
          );
          if (file != null) await _savePhoto(route, file);
        }
      } else {
        final files = await picker.pickMultipleMedia(imageQuality: 85);
        for (final file in files) {
          if (!mounted) return;
          if (_looksLikeVideo(file)) {
            await _saveVideo(route, file);
          } else {
            await _savePhoto(route, file);
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.photoAddFailedGeneric('$e'))));
    }
  }

  Future<RouteMediaType?> _pickCameraMediaType() {
    final l10n = AppLocalizations.of(context)!;
    return showModalBottomSheet<RouteMediaType>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: Text(l10n.photoMediaTypeLabel),
              onTap: () => Navigator.pop(context, RouteMediaType.photo),
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: Text(l10n.videoMediaTypeLabel),
              onTap: () => Navigator.pop(context, RouteMediaType.video),
            ),
          ],
        ),
      ),
    );
  }

  /// Tries the photo's own EXIF GPS first; if that comes up empty (common on
  /// the web build, where browsers often strip it), offers manual placement.
  Future<void> _savePhoto(GpxRoute route, XFile file) async {
    final bytes = await file.readAsBytes();
    final gps = await extractExifGps(bytes);
    if (!mounted) return;

    var location = gps;
    if (location == null) {
      location = await _pickLocationManually(route);
      if (!mounted) return;
    }

    await context.read<PhotoRepository>().add(
      routeId: route.id,
      bytes: bytes,
      lat: location?.latitude,
      lng: location?.longitude,
    );
  }

  /// Videos don't get automatic location detection at all - reading GPS
  /// metadata out of a video container reliably across formats/platforms
  /// isn't something we can do with a simple, robust library - so this
  /// always offers manual placement instead.
  Future<void> _saveVideo(GpxRoute route, XFile file) async {
    final bytes = await file.readAsBytes();
    if (!mounted) return;

    final location = await _pickLocationManually(route);
    if (!mounted) return;

    await context.read<PhotoRepository>().add(
      routeId: route.id,
      bytes: bytes,
      lat: location?.latitude,
      lng: location?.longitude,
      type: RouteMediaType.video,
    );
  }

  /// Asks whether the user wants to place a pin for a photo/video with no
  /// known location, and if so opens [LocationPickerScreen] centered on the
  /// route. Returns null if they skip, or don't confirm a point.
  Future<LatLng?> _pickLocationManually(GpxRoute route) async {
    final l10n = AppLocalizations.of(context)!;
    final wantsToPlace = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.noLocationFoundTitle),
        content: Text(l10n.noLocationFoundMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.skipLocationButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.pickOnMapButton),
          ),
        ],
      ),
    );
    if (wantsToPlace != true || !mounted) return null;

    final center = LatLng(
      (route.north + route.south) / 2,
      (route.east + route.west) / 2,
    );
    return Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(initialCenter: center),
      ),
    );
  }

  void _openPhotoViewer(GpxRoute route, String photoId) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (_) =>
          PhotoViewerDialog(routeId: route.id, initialPhotoId: photoId),
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

        final days = _days;
        final stops = _stops;
        final overnights = _overnights;
        final geotaggedPhotoCount = context
            .watch<PhotoRepository>()
            .photosFor(route.id)
            .where((p) => p.hasLocation)
            .length;

        return Scaffold(
          body: Stack(
            children: [
              Positioned.fill(child: _buildMap(route, stops, overnights)),
              if (_trackDrawing)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildTopBar(context, route),
              ),
              Positioned(
                left: 0,
                right: 88,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: RoutePhotoStrip(
                      routeId: route.id,
                      onAddMedia: () => _addMedia(route),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 16,
                bottom: 24,
                child: Column(
                  children: [
                    if (days.length > 1) ...[
                      FloatingActionButton.small(
                        heroTag: 'dayFilter',
                        tooltip: AppLocalizations.of(context)!.dayFilterTooltip,
                        onPressed: () => _showDayFilterPicker(days),
                        child: const Icon(Icons.filter_alt),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (stops.isNotEmpty) ...[
                      FloatingActionButton.small(
                        heroTag: 'toggleStops',
                        tooltip: _showStops
                            ? AppLocalizations.of(context)!.hideStopsTooltip
                            : AppLocalizations.of(context)!.showStopsTooltip,
                        onPressed: () =>
                            setState(() => _showStops = !_showStops),
                        child: Icon(
                          _showStops
                              ? Icons.pause_circle_filled
                              : Icons.pause_circle_outline,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (geotaggedPhotoCount > 0) ...[
                      FloatingActionButton.small(
                        heroTag: 'togglePhotoPins',
                        tooltip: _showPhotoPins
                            ? AppLocalizations.of(context)!.hidePhotoPinsTooltip
                            : AppLocalizations.of(context)!.showPhotoPinsTooltip,
                        onPressed: () =>
                            setState(() => _showPhotoPins = !_showPhotoPins),
                        child: Icon(
                          _showPhotoPins
                              ? Icons.photo_camera
                              : Icons.photo_camera_outlined,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
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
                    ValueListenableBuilder<double>(
                      valueListenable: _rotationDeg,
                      builder: (context, rotationDeg, _) {
                        if (rotationDeg.abs() <= 0.5) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: FloatingActionButton.small(
                            heroTag: 'northUp',
                            tooltip:
                                AppLocalizations.of(context)!.northUpTooltip,
                            onPressed: _resetNorth,
                            child: Transform.rotate(
                              angle: -rotationDeg * pi / 180,
                              child: const Icon(Icons.navigation),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
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

  Widget _buildMap(
    GpxRoute route,
    List<DetectedStop> stops,
    List<OvernightStay> overnights,
  ) {
    if (_error != null) {
      return Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)),
      );
    }
    if (!_mapBootstrapped) {
      return const Center(child: CircularProgressIndicator());
    }

    final start = _trackStart;
    final end = _trackEnd;
    final center = start ??
        LatLng(
          (route.north + route.south) / 2,
          (route.east + route.west) / 2,
        );
    final l10n = AppLocalizations.of(context)!;
    final trackReady = _points != null && !_trackDrawing;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(initialCenter: center, initialZoom: 12),
      children: [
        TileLayer(
          // Force a fresh tile cache when the rider switches base style -
          // otherwise leftover tiles from the previous host briefly mix in
          // ("kare kare farklı harita") while the new ones load.
          key: ValueKey(_mapStyle.id),
          urlTemplate: _mapStyle.urlTemplate,
          subdomains: _mapStyle.subdomains,
          tileProvider: createRideAtlasTileProvider(),
          maxNativeZoom: _mapStyle.maxNativeZoom,
          // Evict failed tiles when pruned so a later pan/zoom can retry
          // just those cells - never blast-reset the whole layer (that
          // caused the topo flicker when OpenTopoMap rate-limited).
          evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
        ),
        PolylineLayer(polylines: _polylines),
        MarkerLayer(
          markers: [
            if (trackReady)
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
            if (trackReady && _showStops) ...[
              for (final stop in stops)
                Marker(
                  point: stop.location,
                  width: 30,
                  height: 30,
                  child: GestureDetector(
                    onTap: () => _zoomToStop(stop.location),
                    child: Tooltip(
                      message:
                          '${l10n.rest} · ${formatAnalysisDuration(l10n, stop.duration)}',
                      child: const Icon(
                        Icons.pause_circle_filled,
                        color: Color(0xFFFF8F00),
                        size: 26,
                      ),
                    ),
                  ),
                ),
              for (final stay in overnights)
                Marker(
                  point: stay.location,
                  width: 30,
                  height: 30,
                  child: GestureDetector(
                    onTap: () => _zoomToStop(stay.location),
                    child: Tooltip(
                      message: stay.duration == null
                          ? l10n.overnightLabel
                          : '${l10n.overnightLabel} · ${formatAnalysisDuration(l10n, stay.duration!)}',
                      child: const Icon(
                        Icons.hotel,
                        color: Color(0xFF5E35B1),
                        size: 26,
                      ),
                    ),
                  ),
                ),
            ],
            if (start != null && _polylines.isNotEmpty)
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
            if (end != null && _polylines.isNotEmpty)
              Marker(
                point: end,
                width: 36,
                height: 36,
                child: Icon(
                  _trackDrawing ? Icons.navigation : Icons.location_on,
                  color: const Color(0xFFD32F2F),
                  size: _trackDrawing ? 28 : 36,
                ),
              ),
            if (trackReady && _showPhotoPins)
              for (final photo
                  in context
                      .watch<PhotoRepository>()
                      .photosFor(route.id)
                      .where((p) => p.hasLocation))
                Marker(
                  point: photo.latLng!,
                  width: 44,
                  height: 44,
                  child: GestureDetector(
                    onTap: () => _openPhotoViewer(route, photo.id),
                    child: Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.fromBorderSide(
                          BorderSide(color: Colors.white, width: 2),
                        ),
                        boxShadow: [
                          BoxShadow(color: Colors.black38, blurRadius: 4),
                        ],
                      ),
                      child: PhotoThumb(
                        photoId: photo.id,
                        size: 40,
                        circle: true,
                        isVideo: photo.isVideo,
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

  /// The ride's month and year (no day) - e.g. "Ocak 2023" - taken from the
  /// track's own first point, not [GpxRoute.importedAt] (which is just when
  /// the file was added to the app, often long after the actual ride). Null
  /// until points have loaded.
  String? _routeDateLabel(BuildContext context) {
    final points = _points;
    final firstPointTime = (points != null && points.isNotEmpty)
        ? points.first.time
        : null;
    if (firstPointTime == null) return null;
    return DateFormat(
      'MMMM yyyy',
      Localizations.localeOf(context).languageCode,
    ).format(firstPointTime);
  }

  Widget _buildTopBar(BuildContext context, GpxRoute route) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _RoundIconButton(
                  icon: Icons.arrow_back,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                _RoundIconButton(
                  icon: Icons.list,
                  onPressed: () => _showList(route),
                ),
                const Spacer(),
                _RoundIconButton(
                  icon: Icons.insights,
                  onPressed: _points == null
                      ? null
                      : () => _openAnalysis(route),
                ),
                const SizedBox(width: 8),
                _RoundIconButton(
                  icon: Icons.ios_share,
                  onPressed: () => _share(route),
                ),
                const SizedBox(width: 8),
                _RoundIconButton(
                  icon: Icons.settings,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                ),
                const SizedBox(width: 8),
                const RecordingRowIcon(),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 6),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    cleanRouteName(route.name),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_routeDateLabel(context) case final dateLabel?)
                    Text(
                      dateLabel,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Centered picker for the map's base tile style (street, satellite, etc.),
/// opened from the small layers button on the map screen.
class MapStylePickerDialog extends StatelessWidget {
  const MapStylePickerDialog({
    super.key,
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

/// Multi-select picker for which day(s) of a multi-day trip to draw on the
/// map (e.g. only day 1, or just days 3 and 7). `selected: null` means every
/// day is shown - the default.
class _DayFilterDialog extends StatefulWidget {
  const _DayFilterDialog({
    required this.days,
    required this.selected,
    required this.onChanged,
  });

  final List<DayStats> days;
  final Set<int>? selected;
  final ValueChanged<Set<int>?> onChanged;

  @override
  State<_DayFilterDialog> createState() => _DayFilterDialogState();
}

class _DayFilterDialogState extends State<_DayFilterDialog> {
  late Set<int> _checked;

  @override
  void initState() {
    super.initState();
    _checked =
        widget.selected?.toSet() ?? widget.days.map((d) => d.dayNumber).toSet();
  }

  void _toggle(int dayNumber, bool? value) {
    setState(() {
      if (value == true) {
        _checked.add(dayNumber);
      } else if (_checked.length > 1) {
        // Keep at least one day checked so the map is never left blank.
        _checked.remove(dayNumber);
      }
    });
    widget.onChanged(
      _checked.length == widget.days.length ? null : Set.of(_checked),
    );
  }

  void _showAll() {
    setState(() => _checked = widget.days.map((d) => d.dayNumber).toSet());
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final dateFmt = DateFormat(
      'd MMM',
      Localizations.localeOf(context).languageCode,
    );
    final allChecked = _checked.length == widget.days.length;

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
                      l10n.dayFilterTitle,
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
              TextButton.icon(
                onPressed: allChecked ? null : _showAll,
                icon: const Icon(Icons.done_all),
                label: Text(l10n.dayFilterShowAll),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.days.length,
                  itemBuilder: (context, i) {
                    final day = widget.days[i];
                    return CheckboxListTile(
                      value: _checked.contains(day.dayNumber),
                      onChanged: (v) => _toggle(day.dayNumber, v),
                      secondary: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: day.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: Text(
                        '${l10n.dayLabel(day.dayNumber)} · ${dateFmt.format(day.date)}',
                      ),
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
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      _selectedIds.clear();
    });
  }

  void _showSelectedOnMap() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MultiRouteMapScreen(routeIds: _selectedIds.toList()),
      ),
    );
  }

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
    } on DuplicateRouteException catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.duplicateRouteMessage(e.existing.name))),
      );
      final navigator = Navigator.of(context);
      navigator.pop();
      navigator.pushReplacement(
        MaterialPageRoute(
          builder: (_) => RouteMapScreen(routeId: e.existing.id),
        ),
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
                  if (_selectionMode)
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: l10n.exitSelectionTooltip,
                      onPressed: _toggleSelectionMode,
                    ),
                  Expanded(
                    child: Text(
                      _selectionMode
                          ? l10n.selectedCountTitle(_selectedIds.length)
                          : l10n.routesDialogTitle,
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  if (!_selectionMode && routes.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.checklist),
                      tooltip: l10n.selectRoutesTooltip,
                      onPressed: _toggleSelectionMode,
                    ),
                  if (!_selectionMode)
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
                    final isCurrent = r.id == widget.currentRouteId;
                    final isChecked = _selectedIds.contains(r.id);
                    return ListTile(
                      leading: _selectionMode
                          ? Checkbox(
                              value: isChecked,
                              onChanged: (v) => setState(() {
                                if (v ?? false) {
                                  _selectedIds.add(r.id);
                                } else {
                                  _selectedIds.remove(r.id);
                                }
                              }),
                            )
                          : Icon(
                              Icons.route,
                              color: isCurrent
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outline,
                            ),
                      title: Text(
                        r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text('${r.distanceKm.toStringAsFixed(1)} km'),
                      selected: _selectionMode ? isChecked : isCurrent,
                      trailing: _selectionMode
                          ? null
                          : PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'rename') {
                                  _renameRoute(context, r);
                                }
                                if (value == 'editAnomalies') {
                                  _editRouteAnomalies(context, r);
                                }
                                if (value == 'delete') {
                                  _deleteRoute(context, r, isCurrent);
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text(l10n.rename),
                                ),
                                PopupMenuItem(
                                  value: 'editAnomalies',
                                  child: Text(l10n.anomalyEditorMenuItem),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(l10n.delete),
                                ),
                              ],
                            ),
                      onTap: _selectionMode
                          ? () => setState(() {
                              if (isChecked) {
                                _selectedIds.remove(r.id);
                              } else {
                                _selectedIds.add(r.id);
                              }
                            })
                          : () {
                              Navigator.pop(context);
                              if (!isCurrent) {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        RouteMapScreen(routeId: r.id),
                                  ),
                                );
                              }
                            },
                    );
                  },
                ),
              ),
              if (_selectionMode && _selectedIds.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 12),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _showSelectedOnMap,
                      icon: const Icon(Icons.map),
                      label: Text(l10n.showOnMapButton(_selectedIds.length)),
                    ),
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

Future<void> _editRouteAnomalies(BuildContext context, GpxRoute route) async {
  final l10n = AppLocalizations.of(context)!;
  final changed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => RouteAnomalyEditorScreen(route: route),
    ),
  );
  if (changed == true && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.anomalyEditorSaved)));
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
  await context.read<PhotoRepository>().deleteForRoute(route.id);
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
