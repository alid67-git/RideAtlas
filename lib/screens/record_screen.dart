import 'dart:async';
import 'dart:convert';
import 'dart:math' show max, min;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:photo_manager/photo_manager.dart' hide LatLng;
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/base_map_style.dart';
import '../models/gpx_route.dart';
import '../models/track_point.dart';
import '../repositories/live_stats_layout_controller.dart';
import '../repositories/photo_repository.dart';
import '../repositories/route_repository.dart';
import '../repositories/vehicle_icon_controller.dart';
import '../services/battery_info.dart';
import '../services/battery_optimization.dart';
import '../services/daily_analysis.dart' show colorForDay;
import '../services/exif_gps.dart';
import '../services/gallery_scan.dart';
import '../services/gps_recorder.dart';
import '../services/live_location.dart';
import '../services/gpx_parser.dart';
import '../services/app_update_controller.dart';
import '../services/map_camera_fit.dart';
import '../services/track_heading.dart';
import '../services/track_io.dart';
import '../widgets/app_update_ui.dart';
import '../widgets/heading_cone.dart';
import '../widgets/recording_indicator.dart';
import '../widgets/satellite_count_badge.dart';
import '../widgets/vehicle_marker.dart';
import 'analysis_sheet.dart' show AnalysisStatCard;
import 'location_picker_screen.dart';
import 'map_screen.dart' show MapStylePickerDialog;
import 'ride_photo_picker_screen.dart';
import 'settings_screen.dart';

const _metaBoxName = 'rideatlas_meta';
const _mapStyleKey = 'base_map_style_id';

/// True on a native Android build, where [GpsRecorder] runs a foreground
/// service and recording survives the app being minimized. Everywhere else
/// (web, other platforms) recording only continues while this screen is the
/// active, visible tab/app.
final _supportsBackgroundRecording =
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Records a ride live using [GpsRecorder] and, once finished, saves it
/// through the same import pipeline as a regular GPX file. [GpsRecorder]
/// lives above the Navigator (see main.dart's providers), so leaving this
/// screen - back button, navigating elsewhere - never stops a recording in
/// progress; [RecordingIndicatorOverlay] shows a floating pill back to it
/// from anywhere in the app. On Android, the recording itself also survives
/// the whole app being minimized (a foreground service); on other platforms
/// it only runs while some tab/window of the app stays open - see
/// AppLocalizations.recordingForegroundNotice for that case.
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key, this.initialShowMap = false});

  /// When returning from home/list while a ride is already running: `true`
  /// opens the live map with the track; `false` opens the text/stats page.
  final bool initialShowMap;

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen>
    with TickerProviderStateMixin {
  /// How much bigger than the vehicle marker itself the heading cone's
  /// bounding box is, so the cone has room to fan out beyond the icon.
  static const _coneMarkerScale = 2.3;

  final _mapController = MapController();
  late final AnimationController _rotationController;

  /// Drives the info page's slowly-breathing background gradient/glow - a
  /// single continuous ticker (hence [TickerProviderStateMixin] instead of
  /// [SingleTickerProviderStateMixin], since [_rotationController] already
  /// needs one) reused for both the gradient shift and the glow blobs'
  /// opacity pulse, so they stay in sync.
  late final AnimationController _bgController;
  double? _lastAcceptedHeading;
  DateTime? _lastAcceptedHeadingTime;
  Timer? _tickTimer;
  bool _starting = false;
  bool _saving = false;

  /// True once recording has started and the rider has switched to the map
  /// page (see [_buildInfoPage]/[_buildMapPage]). Recording always opens on
  /// the info page - the map is one tap away via the toggle button in either
  /// page's header - unless [RecordScreen.initialShowMap] asked for the map
  /// (e.g. home locate while a ride is already running).
  bool _showMap = false;

  /// Same Hive-backed base map style as the home / route map screens, so
  /// picking Topo (or satellite, dark, ...) on any map sticks everywhere -
  /// including the live recording map, which previously always forced
  /// street tiles.
  BaseMapStyle _mapStyle = kBaseMapStyles.first;

  /// Optional saved GPX routes drawn under the live track so the rider can
  /// follow / compare against a previous ride. Empty until they pick some.
  List<Polyline> _referencePolylines = const [];
  Set<String> _referenceRouteIds = {};
  Timer? _overlayRevealTimer;

  GpsRecorder get _recorder => context.read<GpsRecorder>();

  /// Whether the FlutterMap is currently the visible page. Idle always
  /// shows the map (see [build]); once recording, [_showMap] tracks the
  /// rider's info/map toggle. Camera work (centering, course-up follow)
  /// only makes sense while this is true - [_showMap] alone misses the
  /// idle case, which left the idle map stuck wherever it opened.
  bool get _mapVisible => _showMap || _recorder.isIdle;

  /// Idle map position comes from a Dart [Geolocator] stream. Once a
  /// recording has track points, course-up follow is driven by the same
  /// [GpsRecorder] tip that draws the red line (last 2–3 points → location
  /// + heading). Using a second GPS stream for the camera while the line
  /// came from native FGS made the tip creep up-screen then "flow down"
  /// as the camera tween chased a different fix.
  StreamSubscription<Position>? _liveLocationSub;
  LatLng? _currentLocation;
  bool _centeredOnce = false;

  /// Point-count at the last track-driven follow update - skip no-op
  /// [GpsRecorder] notifies (timer ticks, pause flags, …).
  int _lastFollowPointCount = 0;
  GpsRecorder? _recorderListened;

  /// Where the vehicle marker is actually drawn. While course-up follow is
  /// active this is driven by the *same* tween as the camera (see
  /// [_animateCameraTo]) so the marker stays glued to the screen center
  /// instead of jumping ahead of the gliding camera on every GPS fix -
  /// that desync was the long-standing "creeps up the screen, then flows
  /// back down" pumping motion: the marker snapped to the new fix
  /// instantly (up-screen, since travel direction points up) while the
  /// camera took ~2s to catch up (dragging it back down). A ValueNotifier
  /// rather than setState keeps the per-frame updates scoped to the
  /// MarkerLayer alone.
  final _markerLocation = ValueNotifier<LatLng?>(null);

  /// The in-flight camera animation, tracked so a new GPS fix can detach
  /// the previous one before starting its own. Previously cleanup relied
  /// on `forward().whenComplete(...)`, which never fires for an animation
  /// that gets stopped mid-flight - and with a fix every ~2s retargeting a
  /// ~2s glide, essentially *every* animation was stopped mid-flight, so
  /// stale listeners piled up on the shared controller for the entire
  /// ride (thousands per hour), each still writing its outdated camera
  /// position every frame: wasted CPU/heat and visible fighting/stutter.
  CurvedAnimation? _cameraAnimation;
  VoidCallback? _cameraAnimationListener;

  /// How many track points had been recorded at the moment of the last
  /// mid-ride save, or -1 if this session hasn't been saved yet. Reset asks
  /// for confirmation only when there's data newer than the last save.
  int _savedPointCount = -1;

  /// GPS course-over-ground in degrees (0-360, clockwise from north), from
  /// the same position stream - null until the device reports one (it
  /// needs to actually be moving to be meaningful).
  double? _currentHeading;

  /// True while the map should keep auto-centering on the live position,
  /// rotated to keep the direction of travel pointing up (course-up), like
  /// a normal navigation app. Any user-driven map interaction (drag, pinch,
  /// fling, ...) turns this off, so panning around to look at the
  /// surroundings isn't constantly fought by the auto-follow; the recenter
  /// button turns it back on (see [_recenter]).
  bool _followMe = true;

  /// Whether a [MapEvent] represents the rider actually touching/panning
  /// the map, as opposed to flutter_map's own internal bookkeeping events
  /// (constructing the map fresh when switching from the info page back to
  /// the map tab fires a [MapEventSource.nonRotatedSizeChange] the instant
  /// it's laid out, for one) - those aren't gestures and shouldn't silently
  /// cancel course-up follow the way a real drag/pinch should. This was the
  /// actual root cause behind the map seemingly refusing to rotate to
  /// course-up: follow mode was being turned off on essentially every
  /// screen switch, well before the rider ever touched anything.
  static bool _isUserMapGesture(MapEventSource source) {
    switch (source) {
      case MapEventSource.dragStart:
      case MapEventSource.onDrag:
      case MapEventSource.dragEnd:
      case MapEventSource.multiFingerGestureStart:
      case MapEventSource.onMultiFinger:
      case MapEventSource.multiFingerEnd:
      case MapEventSource.flingAnimationController:
      case MapEventSource.doubleTapZoomAnimationController:
      case MapEventSource.scrollWheel:
      case MapEventSource.cursorKeyboardRotation:
        return true;
      default:
        return false;
    }
  }

  late final StreamSubscription<MapEvent> _mapEventSub;

  @override
  void initState() {
    super.initState();
    recordScreenVisible.value = true;
    // Seed before first build so a return-from-home locate opens the map
    // with the live track instead of the info page.
    _showMap = widget.initialShowMap;
    _rotationController = AnimationController(
      vsync: this,
      // Match the ~2s native GPS cadence so one camera glide is still
      // finishing when the next fix retargets it (continuous motion
      // instead of snap-and-sit).
      duration: const Duration(milliseconds: 1800),
    );
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat(reverse: true);
    _startLiveLocation();
    _loadMapStyle();
    _mapEventSub = _mapController.mapEventStream.listen((event) {
      if (_isUserMapGesture(event.source) && _followMe) {
        // Stop any in-flight glide so a pan isn't yanked by the last GPS
        // tween for up to ~1.8s after the rider touches the map.
        _cancelCameraAnimation();
        setState(() => _followMe = false);
      }
    });
    // Refreshes the elapsed-time label even between GPS fixes.
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _recorder.isRecording) setState(() {});
    });
    // Same shared update check as the home screen - so the banner also
    // appears here if the rider jumped straight into recording.
    if (AppUpdateController.isSupported) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<AppUpdateController>().check();
      });
    }
    if (widget.initialShowMap) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_showMap) return;
        final location = _recorder.currentLatLng ?? _currentLocation;
        if (location != null) {
          _followMe = true;
          _mapController.move(location, 15);
          _markerLocation.value = location;
          kickMapTileLayer(_mapController);
          _applyRotation();
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final recorder = context.read<GpsRecorder>();
    if (!identical(recorder, _recorderListened)) {
      _recorderListened?.removeListener(_onRecorderChanged);
      _recorderListened = recorder;
      _recorderListened!.addListener(_onRecorderChanged);
    }
  }

  /// True while recording and the red track already has at least one point
  /// — camera/marker must follow that tip, not the parallel Geolocator stream.
  bool get _followFromTrack =>
      !_recorder.isIdle && _recorder.points.isNotEmpty;

  void _onRecorderChanged() {
    if (!mounted) return;
    if (_recorder.isIdle) {
      _lastFollowPointCount = 0;
      return;
    }
    final points = _recorder.points;
    if (points.isEmpty) return;
    if (points.length == _lastFollowPointCount) return;
    _lastFollowPointCount = points.length;
    _followFromTrackTip(points);
  }

  /// Frames course-up from the drawn track: tip = last point; heading from
  /// the last 2–3 points (old → new), matching what the red polyline shows.
  void _followFromTrackTip(List<TrackPoint> points) {
    final tip = points.last.latLng;
    final recent = _recentLatLngs(points);
    final rawHeading = headingFromRecentTrackPoints(recent);
    final time = points.last.time ?? DateTime.now();
    final heading = rawHeading != null
        ? _plausibleHeading(rawHeading, time)
        : (_recorder.currentHeading ?? _currentHeading);

    setState(() {
      _currentLocation = tip;
      if (heading != null) _currentHeading = heading;
    });

    if (!_centeredOnce) {
      _centeredOnce = true;
      _markerLocation.value = tip;
      if (_mapVisible) {
        _mapController.move(tip, 15);
        kickMapTileLayer(_mapController);
      }
      return;
    }

    if (_followMe && _mapVisible) {
      _animateCameraTo(location: tip, heading: heading);
    } else {
      _markerLocation.value = tip;
    }
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

  /// Lets the rider optionally overlay one or more saved GPX tracks under
  /// the live recording line (e.g. to retrace yesterday's ride). Empty
  /// selection removes the overlays.
  Future<void> _pickReferenceRoutes() async {
    final l10n = AppLocalizations.of(context)!;
    final routes = context.read<RouteRepository>().routes;
    if (routes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.recordOverlayNoRoutes)),
      );
      return;
    }

    final selected = Set<String>.from(_referenceRouteIds);
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
    await _applyReferenceRoutes(selected);
  }

  /// Clears overlays immediately, then parses each selected GPX off the UI
  /// isolate and grows the polyline in batches so selecting many long
  /// tracks never freezes the recording screen.
  ///
  /// After the first readable route is known, frames the map MediaAtlas-style:
  /// one selected track fills the window; several zoom out to cover all
  /// (plus any live recording points already on the map).
  Future<void> _applyReferenceRoutes(Set<String> ids) async {
    _overlayRevealTimer?.cancel();
    if (ids.isEmpty) {
      setState(() {
        _referenceRouteIds = {};
        _referencePolylines = const [];
      });
      return;
    }

    setState(() {
      _referenceRouteIds = ids;
      _referencePolylines = const [];
    });

    final repo = context.read<RouteRepository>();
    final byId = {for (final r in repo.routes) r.id: r};
    final selectedRoutes = [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
    // Fit as soon as metadata is known - don't wait for XML parse/reveal.
    _fitLoadedTracks(selectedRoutes);

    var colorIndex = 1; // skip red - reserved for the live track
    final built = <Polyline>[];

    for (final id in ids) {
      if (!mounted) return;
      final route = byId[id];
      if (route == null) continue;
      try {
        final xml = await repo.readTrackContent(route);
        if (!mounted) return;
        final parsed = await compute(parseAndFilterTrackXml, xml);
        if (!mounted) return;
        final points = [for (final p in parsed.points) p.latLng];
        if (points.length < 2) continue;
        final color = colorForDay(colorIndex);
        colorIndex++;
        await _revealOverlayPolyline(built, points, color);
      } catch (_) {
        // Skip unreadable routes; keep whatever else loaded.
      }
    }
  }

  /// MediaAtlas-style: frame [routes] (1 → that track, N → union). When a
  /// live recording already has points, those are included too.
  void _fitLoadedTracks(List<GpxRoute> routes) {
    if (!_mapVisible) return;
    var bounds = boundsForRoutes(routes);
    bounds = extendBoundsWithPoints(
      bounds,
      [for (final p in _recorder.points) p.latLng],
    );
    if (bounds == null) return;
    _cancelCameraAnimation();
    setState(() => _followMe = false);
    _mapController.rotate(0);
    fitMapToBounds(
      _mapController,
      bounds: bounds,
      padding: const EdgeInsets.fromLTRB(48, 240, 48, 170),
    );
  }

  Future<void> _revealOverlayPolyline(
    List<Polyline> built,
    List<LatLng> points,
    Color color,
  ) async {
    if (points.length < 150) {
      built.add(Polyline(points: points, strokeWidth: 4, color: color));
      if (!mounted) return;
      setState(() => _referencePolylines = List<Polyline>.from(built));
      return;
    }

    final total = points.length;
    final batch = max(30, min(800, (total / 60).ceil()));
    final done = Completer<void>();
    var shown = 0;
    final slot = built.length;
    built.add(Polyline(points: [points.first], strokeWidth: 4, color: color));

    _overlayRevealTimer?.cancel();
    _overlayRevealTimer = Timer.periodic(const Duration(milliseconds: 16), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        if (!done.isCompleted) done.complete();
        return;
      }
      shown = min(total, shown + batch);
      built[slot] = Polyline(
        points: points.sublist(0, shown),
        strokeWidth: 4,
        color: color,
      );
      setState(() => _referencePolylines = List<Polyline>.from(built));
      if (shown >= total) {
        timer.cancel();
        if (!done.isCompleted) done.complete();
      }
    });
    await done.future;
  }

  /// Switches from the info page to the map and re-enables course-up follow.
  /// The map stays mounted under an [Offstage] while the info page is
  /// showing (see [build]), so [MapController] stays attached - we only
  /// need to snap to the latest position/heading.
  void _switchToMap() {
    setState(() {
      _showMap = true;
      _followMe = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_showMap) return;
      final location = _recorder.currentLatLng ?? _currentLocation;
      final heading = _headingFromTrackOrLive;
      if (location != null) {
        _animateCameraTo(location: location, heading: heading);
      } else if (heading != null) {
        _animateCameraTo(heading: heading);
      }
    });
  }

  /// Prefer track-derived course while recording; fall back to live GPS COG.
  double? get _headingFromTrackOrLive {
    final points = _recorder.points;
    if (points.length >= 2) {
      final raw = headingFromRecentTrackPoints(_recentLatLngs(points));
      if (raw != null) {
        return _plausibleHeading(raw, points.last.time ?? DateTime.now());
      }
    }
    return _recorder.currentHeading ?? _currentHeading;
  }

  /// Last up-to-three track positions (old → new) for course-up heading.
  static List<LatLng> _recentLatLngs(List<TrackPoint> points) {
    if (points.length <= 3) {
      return [for (final p in points) p.latLng];
    }
    final n = points.length;
    return [
      points[n - 3].latLng,
      points[n - 2].latLng,
      points[n - 1].latLng,
    ];
  }

  /// Snaps the camera to the live GPS fix at a fixed close zoom (same as the
  /// home map's locate button), then resumes course-up follow. Always does
  /// this - even when already following - so a tap never lands mid-tween or
  /// on a leftover overview zoom. Whole-track overview stays on
  /// [_showWholeTrack].
  Future<void> _recenter() async {
    _cancelCameraAnimation();
    LatLng? location = _recorder.currentLatLng;
    if (location == null) {
      final pos = await fetchFreshDevicePosition();
      if (pos != null) {
        location = LatLng(pos.latitude, pos.longitude);
        if (mounted) {
          setState(() {
            _currentLocation = location;
            _currentHeading = pos.heading.isFinite && pos.heading >= 0
                ? pos.heading
                : _currentHeading;
          });
        }
      }
    }
    location ??= _currentLocation;
    setState(() => _followMe = true);
    if (location != null) {
      _mapController.move(location, 15);
      _markerLocation.value = location;
      kickMapTileLayer(_mapController);
    }
    _applyRotation();
  }

  /// Zooms out to fit the live track (and any loaded reference overlays)
  /// on screen, north-up, and stops auto-follow so the overview stays put.
  /// Tapping the recenter button ([_recenter]) returns to the live position.
  void _showWholeTrack() {
    final repo = context.read<RouteRepository>();
    final byId = {for (final r in repo.routes) r.id: r};
    final overlayRoutes = [
      for (final id in _referenceRouteIds)
        if (byId[id] != null) byId[id]!,
    ];
    var bounds = boundsForRoutes(overlayRoutes);
    bounds = extendBoundsWithPoints(
      bounds,
      [for (final p in _recorder.points) p.latLng],
    );
    if (bounds == null) return;
    _fitLoadedTracks(overlayRoutes);
  }

  /// Rotates the map to the live heading (course-up), if known yet.
  void _applyRotation() {
    final heading = _headingFromTrackOrLive;
    if (heading != null) _animateCameraTo(heading: heading);
  }

  /// Rejects a heading reading that implies a physically implausible turn
  /// rate since the last accepted one (a single bad GPS course fix, not a
  /// real maneuver), keeping the last good heading instead of snapping to
  /// noise. Generous enough that even a tight hairpin passes straight
  /// through - unlike averaging several readings together (this file's
  /// previous approach), this never lags behind a genuine curve, since a
  /// real turn is accepted the instant it's seen rather than waiting for
  /// several more fixes to pull a moving average round to it.
  static const _maxHeadingChangeDegPerSec = 60.0;

  double _plausibleHeading(double rawHeading, DateTime time) {
    final lastHeading = _lastAcceptedHeading;
    final lastTime = _lastAcceptedHeadingTime;
    if (lastHeading != null && lastTime != null) {
      final dtSeconds = time.difference(lastTime).inMilliseconds / 1000.0;
      if (dtSeconds > 0) {
        var diff = (rawHeading - lastHeading) % 360;
        if (diff > 180) diff -= 360;
        if (diff < -180) diff += 360;
        if (diff.abs() > _maxHeadingChangeDegPerSec * dtSeconds) {
          return lastHeading;
        }
      }
    }
    _lastAcceptedHeading = rawHeading;
    _lastAcceptedHeadingTime = time;
    return rawHeading;
  }

  /// Animates the map's center and/or rotation to the given target(s)
  /// together, over the same [_rotationController] duration, instead of
  /// snapping instantly - a real GPS chip can't reasonably produce fixes
  /// much faster than about once a second, so without this the map would
  /// otherwise sit still for most of every second and then jump, which
  /// reads as laggy even once the fixes themselves arrive as fast as
  /// they realistically can. Rotation takes the shorter way round (e.g.
  /// 350deg -> 10deg animates as +20, not -340). Reads the map's actual
  /// current center/rotation each call rather than tracking separate
  /// copies of them, so this can't drift out of sync with the map itself.
  void _animateCameraTo({LatLng? location, double? heading}) {
    // Info page keeps the map Offstage but still mounted; skip camera work
    // while it's hidden so we don't fight a zero-size map viewport.
    if (!_mapVisible) return;
    // Detach the previous fix's animation *before* starting this one -
    // see [_cameraAnimation] for why relying on whenComplete leaked a
    // listener on nearly every fix.
    _cancelCameraAnimation();
    final camera = _mapController.camera;
    final startLat = camera.center.latitude;
    final startLng = camera.center.longitude;
    final startRotation = camera.rotation;
    final endLat = location?.latitude ?? startLat;
    final endLng = location?.longitude ?? startLng;
    var endRotation = startRotation;
    if (heading != null) {
      var delta = (heading - startRotation) % 360;
      if (delta > 180) delta -= 360;
      if (delta < -180) delta += 360;
      endRotation = startRotation + delta;
    }
    if (location == null && (endRotation - startRotation).abs() < 0.5) return;

    final zoom = camera.zoom;
    final latTween = Tween<double>(begin: startLat, end: endLat);
    final lngTween = Tween<double>(begin: startLng, end: endLng);
    final rotationTween = Tween<double>(begin: startRotation, end: endRotation);
    // Linear, not eased - this approximates constant real-world motion
    // between two fixes rather than a one-off discrete correction, so
    // decelerating toward the end (like the old easeOut) would read as a
    // stutter right before the next fix retargets it anyway.
    final animation = CurvedAnimation(
      parent: _rotationController,
      curve: Curves.linear,
    );
    void listener() {
      final target = LatLng(
        latTween.evaluate(animation),
        lngTween.evaluate(animation),
      );
      _mapController.moveAndRotate(
        target,
        zoom,
        rotationTween.evaluate(animation),
      );
      // The marker rides the exact same tween as the camera center, so it
      // stays pinned to the screen center throughout the glide instead of
      // jumping ahead and drifting back (see [_markerLocation]).
      if (location != null) _markerLocation.value = target;
    }

    animation.addListener(listener);
    _cameraAnimation = animation;
    _cameraAnimationListener = listener;
    _rotationController
      ..stop()
      ..reset()
      ..forward();
  }

  /// Stops the current camera glide and detaches its listener from the
  /// shared controller. Safe to call when nothing is animating.
  void _cancelCameraAnimation() {
    _rotationController.stop();
    final animation = _cameraAnimation;
    final listener = _cameraAnimationListener;
    if (animation != null && listener != null) {
      animation.removeListener(listener);
    }
    _cameraAnimation = null;
    _cameraAnimationListener = null;
  }

  Future<void> _startLiveLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
    } catch (_) {
      // No geolocation support on this platform/browser - the map still
      // works, just centered on the fallback location until recording
      // starts producing points.
      return;
    }

    _liveLocationSub =
        Geolocator.getPositionStream(
          locationSettings: _supportsBackgroundRecording
              ? AndroidSettings(
                  accuracy: LocationAccuracy.high,
                  distanceFilter: 0,
                  // Match native recording's 2s cadence - a second GPS
                  // stream at 1Hz on top of the FGS was doubling radio/
                  // CPU work and heating phones during long rides.
                  intervalDuration: const Duration(seconds: 2),
                )
              : const LocationSettings(
                  accuracy: LocationAccuracy.high,
                  distanceFilter: 5,
                ),
        ).listen((pos) {
          if (!mounted) return;
          if (!isAcceptableLivePosition(pos)) return;
          // While recording, the drawn track tip owns camera/marker follow.
          // Geolocator still seeds the map before the first native point.
          if (_followFromTrack) return;

          final location = LatLng(pos.latitude, pos.longitude);
          // A heading reading near 0 accuracy/while stationary is noisy
          // GPS jitter, not a real course - ignore it rather than let the
          // map twitch around when stopped. What's left is filtered for
          // physically-implausible single-fix jumps before it ever reaches
          // the map, rather than averaged (averaging lagged behind genuine
          // curves - see _plausibleHeading).
          final heading = (pos.heading >= 0 && pos.speed > 0.5)
              ? _plausibleHeading(pos.heading, pos.timestamp)
              : _currentHeading;
          setState(() {
            _currentLocation = location;
            _currentHeading = heading;
          });
          if (!_centeredOnce) {
            _centeredOnce = true;
            _markerLocation.value = location;
            if (_mapVisible) {
              _mapController.move(location, 15);
              kickMapTileLayer(_mapController);
            }
          } else if (_followMe && _mapVisible) {
            // Position and rotation animate together over the same
            // duration - see _animateCameraTo - rather than the map
            // snapping to the new spot and then separately swinging to
            // the new heading. The vehicle marker is driven by that same
            // animation, so it never jumps ahead of the camera.
            _animateCameraTo(location: location, heading: heading);
          } else {
            // Not following (rider panned away, or map hidden behind the
            // info page) - the marker just tracks the raw fix directly.
            _markerLocation.value = location;
          }
        });
  }

  @override
  void dispose() {
    recordScreenVisible.value = false;
    _recorderListened?.removeListener(_onRecorderChanged);
    _tickTimer?.cancel();
    _overlayRevealTimer?.cancel();
    _liveLocationSub?.cancel();
    _mapEventSub.cancel();
    _cancelCameraAnimation();
    _rotationController.dispose();
    _bgController.dispose();
    _markerLocation.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    // Ask for the two things screen-off recording needs *before* the
    // stream starts, so we don't begin a ride that will silently gap.
    if (_supportsBackgroundRecording) {
      if (!await isIgnoringBatteryOptimizations()) {
        await requestIgnoreBatteryOptimizations();
      }
      if (!mounted) return;
      if (!await _ensureBackgroundLocationPermission()) return;
      if (!mounted) return;
    }

    setState(() => _starting = true);
    final l10nForStart = AppLocalizations.of(context)!;
    final error = await _recorder.start(
      androidNotificationTitle: l10nForStart.recordingNotificationTitle,
      androidNotificationText: l10nForStart.recordingNotificationText,
    );
    if (!mounted) return;
    setState(() => _starting = false);
    if (error != null) {
      final l10n = AppLocalizations.of(context)!;
      if (error == RecordingStartError.backgroundPermissionDenied) {
        await _promptBackgroundLocationSettings();
        return;
      }
      final message = error == RecordingStartError.serviceDisabled
          ? l10n.locationServiceDisabledError
          : l10n.locationPermissionDeniedError;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    setState(() {
      _followMe = true;
      _savedPointCount = -1;
      // Opens on the info page - the map is one tap away via its toggle
      // button - rather than whatever page the rider happened to be
      // looking at before tapping start. Map stays Offstage-mounted so
      // course-up still works the moment they switch back.
      _showMap = false;
    });
  }

  /// Returns true when Android has granted "Allow all the time", or when
  /// this platform doesn't need it. Shows the settings dialog and returns
  /// false if the user still only has while-in-use access.
  Future<bool> _ensureBackgroundLocationPermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.whileInUse) {
      // Second, distinct request is how Android exposes "Allow all the time".
      permission = await Geolocator.requestPermission();
    }
    if (!mounted) return false;
    if (permission == LocationPermission.always) return true;
    await _promptBackgroundLocationSettings();
    if (!mounted) return false;
    return await Geolocator.checkPermission() == LocationPermission.always;
  }

  Future<void> _promptBackgroundLocationSettings() async {
    final l10n = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.backgroundLocationDialogTitle),
        content: Text(l10n.backgroundLocationDialogMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              Geolocator.openAppSettings();
            },
            child: Text(l10n.openSettings),
          ),
        ],
      ),
    );
  }

  /// True when there are recorded points newer than the last mid-ride save
  /// (or any points at all if this session was never saved) - the data a
  /// reset would actually lose.
  bool get _hasUnsavedData {
    final points = _recorder.points;
    return points.isNotEmpty && points.length != _savedPointCount;
  }

  /// Resets the session back to idle, zeroing every stat. Asks for
  /// confirmation only when there's unsaved data to lose - right after a
  /// save there's nothing at risk, so it resets silently. Stays on this
  /// screen (idle map with the start button) rather than popping, so
  /// starting the next ride is one tap away.
  Future<void> _resetRecording() async {
    if (_hasUnsavedData) {
      final l10n = AppLocalizations.of(context)!;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.resetRecordingConfirmTitle),
          content: Text(l10n.resetRecordingConfirmMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.resetRecordingButton),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    _savedPointCount = -1;
    await _recorder.discard();
  }

  /// Saves the ride recorded so far without ending the session - only
  /// reachable while paused (see [_buildControls]). The recorder keeps its
  /// full state (km, timers, pauses), so afterwards the rider chooses:
  /// resume recording (the ride continues cumulatively) or reset to zero
  /// (silently - the data was just saved, nothing is lost). Dismissing the
  /// dialog stays paused.
  Future<void> _saveRecording() async {
    final l10n = AppLocalizations.of(context)!;
    final defaultName = l10n.recordingDefaultName(
      DateFormat(
        'd MMM yyyy HH:mm',
        Localizations.localeOf(context).languageCode,
      ).format(DateTime.now()),
    );
    final controller = TextEditingController(text: defaultName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.saveRecordingTitle),
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
    if (name == null || name.isEmpty || !mounted) return;

    setState(() => _saving = true);
    final repo = context.read<RouteRepository>();
    final batteryStart = _recorder.batteryStartPercent;
    final batteryEnd = await currentBatteryPercent();
    final recordingStart = _recorder.startedAt;
    // Snapshot - the recorder stays alive (still paused) rather than being
    // stopped, so the session can continue after the save.
    final points = _recorder.points;
    final gpx = exportTrack(
      name: name,
      points: points,
      waypoints: const [],
      format: TrackFormat.gpx,
    );
    final bytes = Uint8List.fromList(utf8.encode(gpx));
    final route = await repo.importFromBytes(
      bytes: bytes,
      suggestedFileName: '$name.gpx',
      batteryStartPercent: batteryStart,
      batteryEndPercent: batteryEnd,
      skipDuplicateCheck: true,
    );
    _savedPointCount = points.length;
    if (!mounted) return;
    setState(() => _saving = false);
    if (recordingStart != null) {
      await _offerGalleryMedia(route, recordingStart, points);
      if (!mounted) return;
    }

    final resume = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.recordingSavedTitle),
        content: Text(l10n.recordingSavedMessage),
        actions: [
          TextButton(
            // Just saved, so this resets without asking (see
            // _resetRecording - it only confirms for unsaved data).
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.resetRecordingButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.resumeRecordingButton),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (resume == true) {
      _recorder.resume();
    } else if (resume == false) {
      await _resetRecording();
    }
    // Dismissed (tap outside / back): stay paused, decide later.
  }

  /// Looks for photos/videos the gallery gained during this ride and, if
  /// any turn up, lets the rider pick which to attach. Location is resolved
  /// in order: gallery GPS tag → photo EXIF → nearest recorded track point
  /// at the shot's timestamp (Android often strips MediaStore location, so
  /// the track fallback is what actually places mid-ride shots). Manual
  /// placement is only asked when all three fail. Never blocks saving.
  Future<void> _offerGalleryMedia(
    GpxRoute route,
    DateTime recordingStart,
    List<TrackPoint> trackPoints,
  ) async {
    List<GalleryCandidate> candidates;
    try {
      candidates = await findGalleryMediaBetween(recordingStart, DateTime.now());
    } catch (_) {
      return;
    }
    if (candidates.isEmpty || !mounted) return;

    final selected = await Navigator.of(context).push<List<GalleryCandidate>>(
      MaterialPageRoute(
        builder: (_) => RidePhotoPickerScreen(candidates: candidates),
      ),
    );
    if (selected == null || selected.isEmpty || !mounted) return;

    final photoRepo = context.read<PhotoRepository>();
    for (final candidate in selected) {
      if (!mounted) return;
      final asset = candidate.asset;
      final file = await asset.originFile ?? await asset.file;
      if (file == null) continue;
      final fileBytes = await file.readAsBytes();

      final resolved = await _resolveGalleryMediaLocation(
        asset: asset,
        bytes: fileBytes,
        trackPoints: trackPoints,
      );
      var lat = resolved?.latitude;
      var lng = resolved?.longitude;
      if (lat == null || lng == null) {
        final picked = await _pickLocationManually(route);
        if (!mounted) return;
        lat = picked?.latitude;
        lng = picked?.longitude;
      }
      await photoRepo.add(
        routeId: route.id,
        bytes: fileBytes,
        lat: lat,
        lng: lng,
        type: candidate.mediaType,
      );
    }
  }

  /// Android 10+ often withholds MediaStore lat/lng even when the camera
  /// wrote GPS into the file. Try gallery metadata, then EXIF bytes, then
  /// the live track at the asset's create time (works for videos too).
  Future<LatLng?> _resolveGalleryMediaLocation({
    required AssetEntity asset,
    required Uint8List bytes,
    required List<TrackPoint> trackPoints,
  }) async {
    try {
      final assetLocation = await asset.latlngAsync();
      final lat = assetLocation?.latitude;
      final lng = assetLocation?.longitude;
      if (lat != null && lng != null && !(lat == 0 && lng == 0)) {
        return LatLng(lat, lng);
      }
    } catch (_) {}

    try {
      final fromExif = await extractExifGps(bytes);
      if (fromExif != null) return fromExif;
    } catch (_) {}

    return _locationFromTrackAt(trackPoints, asset.createDateTime);
  }

  /// Picks the track point closest in time to [when], accepting only if
  /// within a few minutes - otherwise the shot is treated as unlocated.
  LatLng? _locationFromTrackAt(List<TrackPoint> points, DateTime when) {
    TrackPoint? best;
    var bestDelta = const Duration(days: 365);
    for (final p in points) {
      final t = p.time;
      if (t == null) continue;
      final d = t.difference(when).abs();
      if (d < bestDelta) {
        bestDelta = d;
        best = p;
      }
    }
    if (best == null || bestDelta > const Duration(minutes: 5)) return null;
    return best.latLng;
  }

  /// Asks whether the user wants to place a pin for a photo/video with no
  /// known location, and if so opens [LocationPickerScreen] centered on the
  /// route. Returns null if they skip, or don't confirm a point. Mirrors
  /// RouteMapScreen's own manual-placement flow for a single added photo.
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

  @override
  Widget build(BuildContext context) {
    final recorder = context.watch<GpsRecorder>();
    // Idle (not recording yet) always shows the map with the start button -
    // the info/map split only matters once there's a ride actually in
    // progress to show stats for.
    if (recorder.isIdle) {
      return _buildMapPage(context, recorder);
    }
    // Keep FlutterMap mounted while the info page is visible so
    // MapController stays attached - tearing it down broke course-up
    // (rotate/move threw or no-oped until the next full remap).
    return Stack(
      fit: StackFit.expand,
      children: [
        TickerMode(
          enabled: _showMap,
          child: Offstage(
            offstage: !_showMap,
            child: _buildMapPage(context, recorder),
          ),
        ),
        if (!_showMap) _buildInfoPage(context, recorder),
      ],
    );
  }

  Widget _buildMapPage(BuildContext context, GpsRecorder recorder) {
    final l10n = AppLocalizations.of(context)!;

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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _RoundIconButton(
                          icon: Icons.arrow_back,
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 8),
                        // Not wrapped in Expanded while recording: the speed
                        // box below sizes itself to its own digits (2 vs 3
                        // figures), and used to sit in a Row alongside the
                        // Süre/Mesafe/Yükseklik box, so a wider speed number
                        // squeezed that box's Expanded share down to an
                        // unreadable sliver. Idle still needs Expanded so
                        // the notice text gets the remaining width to wrap
                        // into.
                        recorder.isIdle
                            ? Expanded(
                                child: _buildStats(context, l10n, recorder),
                              )
                            : _buildStats(context, l10n, recorder),
                        const Spacer(),
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: SatelliteCountBadge(),
                        ),
                        const SizedBox(width: 8),
                        _RoundIconButton(
                          icon: Icons.settings,
                          tooltip: l10n.settingsTitle,
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SettingsScreen(),
                            ),
                          ),
                        ),
                        if (!recorder.isIdle) ...[
                          const SizedBox(width: 8),
                          _RoundIconButton(
                            icon: Icons.dashboard_outlined,
                            tooltip: l10n.recordInfoTabTooltip,
                            onPressed: () => setState(() => _showMap = false),
                          ),
                        ],
                      ],
                    ),
                    // Süre/Mesafe/Yükseklik now live on their own full-width
                    // row below the icon row instead of squeezed next to the
                    // speed box - their width no longer depends on how many
                    // digits the speed number has, or on the icons above.
                    if (!recorder.isIdle) ...[
                      const SizedBox(height: 8),
                      _buildMiniStatsRow(context, l10n, recorder),
                    ],
                    if (context.watch<AppUpdateController>().showBanner) ...[
                      const SizedBox(height: 8),
                      const AppUpdateBanner(),
                    ],
                    if (recorder.isAutoPaused) ...[
                      const SizedBox(height: 8),
                      _buildAutoPausedBanner(context, l10n),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 100,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'recordMapStyle',
                    tooltip: AppLocalizations.of(context)!.mapStyleTitle,
                    onPressed: _showMapStylePicker,
                    child: Icon(_mapStyle.icon),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'recordOverlayRoutes',
                    tooltip: l10n.recordOverlayTooltip,
                    backgroundColor: _referencePolylines.isNotEmpty
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    foregroundColor: _referencePolylines.isNotEmpty
                        ? Theme.of(context).colorScheme.onPrimary
                        : null,
                    onPressed: _pickReferenceRoutes,
                    child: const Icon(Icons.route),
                  ),
                  // Overview of everything recorded so far; the recenter
                  // button below returns to the live position, course-up.
                  if (recorder.points.length > 1) ...[
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      heroTag: 'recordShowWholeTrack',
                      tooltip: l10n.showWholeTrackTooltip,
                      onPressed: _showWholeTrack,
                      child: const Icon(Icons.zoom_out_map),
                    ),
                  ],
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'recordRecenter',
                    tooltip: l10n.recenterTooltip,
                    backgroundColor: _followMe
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    foregroundColor: _followMe
                        ? Theme.of(context).colorScheme.onPrimary
                        : null,
                    onPressed: _recenter,
                    // A compass-needle icon while auto-following (course-up),
                    // the plain dot otherwise - the same visual language most
                    // map/nav apps use for this.
                    child: Icon(
                      _followMe ? Icons.navigation : Icons.my_location,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: Center(child: _buildControls(l10n, recorder)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats(
    BuildContext context,
    AppLocalizations l10n,
    GpsRecorder recorder,
  ) {
    final theme = Theme.of(context);
    if (recorder.isIdle) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
        ),
        child: Text(
          _supportsBackgroundRecording
              ? l10n.recordingBackgroundNoticeAndroid
              : l10n.recordingForegroundNotice,
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The current speed is the one number a rider actually needs to
          // read at a glance while moving, so it gets its own big display;
          // everything else is secondary and stays small. Deliberately not
          // wrapped in Expanded/FittedBox by width - see the caller, which
          // now keeps this box out of any Row it could squeeze.
          _AnimatedNumber(
            value: recorder.currentSpeedKmh,
            builder: (context, value) => Text(
              value.round().toString(),
              style: const TextStyle(
                fontSize: 92,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
          Text(l10n.speedLabel, style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }

  /// Süre/Mesafe/Yükseklik strip, on its own full-width row below the top
  /// icon row - kept separate from the speed box (see [_buildStats]) so its
  /// width never depends on how many digits the speed currently has.
  Widget _buildMiniStatsRow(
    BuildContext context,
    AppLocalizations l10n,
    GpsRecorder recorder,
  ) {
    final theme = Theme.of(context);
    final durationStr = _formatDuration(recorder.elapsed);
    final altitude = recorder.currentAltitude;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
      child: Row(
        children: [
          Expanded(child: _StatRow(label: l10n.duration, value: durationStr)),
          _statDividerVertical(theme),
          Expanded(
            child: _StatRow(
              label: l10n.distance,
              value: '${recorder.distanceKm.toStringAsFixed(2)} km',
            ),
          ),
          _statDividerVertical(theme),
          Expanded(
            child: _StatRow(
              label: l10n.currentAltitudeLabel,
              value: altitude == null ? '—' : '${altitude.round()} m',
            ),
          ),
        ],
      ),
    );
  }

  /// Map page's own auto-paused banner, shown below the mini stats row.
  Widget _buildAutoPausedBanner(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
      child: Text(
        l10n.autoPausedLabel,
        textAlign: TextAlign.center,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onTertiaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// The single accent every card/tile on the info page shares - a
  /// deliberate departure from the earlier per-stat rainbow of colors
  /// (blue/orange/teal/pink/brown/green/red/...), which read as busy and
  /// carnival-like rather than a coherent dashboard. Deliberately a fixed
  /// blue rather than [ThemeData.colorScheme.primary] - the app's own seed
  /// color is red, so the theme's primary/secondary render as a pink/maroon
  /// wash in dark mode, which is exactly the "everything is reddish" look
  /// requested to move away from in favor of a cooler, blue-white weighted
  /// dashboard (the app's other red accents - the record button, discard
  /// button - are untouched, so red hasn't disappeared entirely).
  static const _infoAccent = Color(0xFF4FA3FF);

  Color _cardAccent(ThemeData theme) => _infoAccent;

  /// The default page while recording/paused: speed front and center (the
  /// one number a rider actually cares about mid-ride), duration/rest right
  /// below it, then every other stat and a compact speed/elevation chart -
  /// all sized to fit one screen without scrolling. The map itself is one
  /// tap away via the top-right toggle button, mirroring [_buildMapPage]'s
  /// own toggle so both pages switch from the same corner.
  Widget _buildInfoPage(BuildContext context, GpsRecorder recorder) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final points = recorder.points;
    final speedStats = buildSpeedStats(points);
    final elevationChange = computeElevationChange(points);
    final elevationSamples = buildElevationProfile(points);
    final altitude = recorder.currentAltitude;
    double? maxAltitude;
    double? minAltitude;
    for (final s in elevationSamples) {
      if (maxAltitude == null || s.elevation > maxAltitude) {
        maxAltitude = s.elevation;
      }
      if (minAltitude == null || s.elevation < minAltitude) {
        minAltitude = s.elevation;
      }
    }
    final accent = _cardAccent(theme);
    final layoutController = context.watch<LiveStatsLayoutController>();

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _InfoPageBackground(animation: _bgController)),
          SafeArea(
            child: Column(
              children: [
                Padding(
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
                      const Spacer(),
                      const SatelliteCountBadge(),
                      const SizedBox(width: 8),
                      _RoundIconButton(
                        icon: Icons.settings,
                        tooltip: l10n.settingsTitle,
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _RoundIconButton(
                        icon: Icons.map_outlined,
                        tooltip: l10n.recordMapTabTooltip,
                        onPressed: _switchToMap,
                      ),
                    ],
                  ),
                ),
                if (context.watch<AppUpdateController>().showBanner)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: AppUpdateBanner(),
                  ),
                // Total duration lives here, above the auto-paused banner,
                // rather than paired with "Aktif sürüş süresi" below the
                // hero speed number - that slot now holds "Mola süresi"
                // instead, which is the pairing riders actually want to see
                // at a glance next to how long they've been moving.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(
                        alpha: theme.brightness == Brightness.dark ? 0.20 : 0.12,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: accent.withValues(alpha: 0.35)),
                    ),
                    // Label (with icon) on top, the duration itself centered
                    // below, large - was a single crammed row (icon+label+
                    // value all inline), which read unevenly since the
                    // label and the giant value fought for the same line.
                    // At least double the old titleMedium size, and bigger
                    // than the "large" stat cards below it (titleLarge) -
                    // total duration is the one figure meant to stand out
                    // above everything else on this strip. FittedBox keeps
                    // it from overflowing on narrow screens/long durations.
                    //
                    // No "Toplam süre" text label here anymore - this is
                    // the very first thing on the screen and a big clock
                    // icon next to a big duration already says what it is
                    // without spelling it out.
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(Icons.schedule, size: 28, color: accent),
                          const SizedBox(width: 10),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _formatDuration(
                                recorder.totalDuration ?? Duration.zero,
                              ),
                              style: const TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.w900,
                                height: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (recorder.isAutoPaused)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        l10n.autoPausedLabel,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onTertiaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        // The one number a rider actually needs at a glance -
                        // everything else here is secondary to this. Bigger,
                        // slanted and glowing rather than the plain
                        // displayLarge style used elsewhere, so it reads as
                        // a dashboard's hero figure, not just another label.
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _AnimatedNumber(
                                value: recorder.currentSpeedKmh,
                                builder: (context, value) => Text(
                                  value.round().toString(),
                                  style: TextStyle(
                                    fontSize: 150,
                                    fontWeight: FontWeight.w900,
                                    fontStyle: FontStyle.italic,
                                    letterSpacing: -6,
                                    height: 0.95,
                                    color: theme.colorScheme.onSurface,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                    shadows: [
                                      Shadow(
                                        color: accent.withValues(alpha: 0.55),
                                        blurRadius: 32,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: 20,
                                  left: 6,
                                ),
                                child: Text(
                                  'km/h',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Which cards show and in what order is a
                        // per-rider choice (Settings > Kayıt ekranı
                        // kartları, or press-and-hold directly on a card
                        // below) rather than fixed here. Each row is
                        // Expanded so the cards grow to fill whatever
                        // vertical space is left instead of a small stack
                        // sitting above empty screen.
                        Expanded(
                          child: Column(
                            children: [
                              for (final row in _pairUp(
                                layoutController.visibleOrder,
                              ))
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: row.length == 1
                                        ? _draggableStatCard(
                                            row[0],
                                            layoutController,
                                            l10n,
                                            recorder,
                                            speedStats,
                                            elevationChange,
                                            altitude,
                                            maxAltitude,
                                            minAltitude,
                                            accent,
                                          )
                                        : Row(
                                            // Without this the row's own
                                            // height only wraps its (small)
                                            // content and centers it in the
                                            // Expanded slot above - stretch
                                            // makes each card's colored box
                                            // actually fill that slot.
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Expanded(
                                                child: _draggableStatCard(
                                                  row[0],
                                                  layoutController,
                                                  l10n,
                                                  recorder,
                                                  speedStats,
                                                  elevationChange,
                                                  altitude,
                                                  maxAltitude,
                                                  minAltitude,
                                                  accent,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: _draggableStatCard(
                                                  row[1],
                                                  layoutController,
                                                  l10n,
                                                  recorder,
                                                  speedStats,
                                                  elevationChange,
                                                  altitude,
                                                  maxAltitude,
                                                  minAltitude,
                                                  accent,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: _buildControls(l10n, recorder)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Thin vertical separator between the duration/distance/altitude
  /// columns, so their values read as distinct fields instead of running
  /// into each other on narrow screens.
  Widget _statDividerVertical(ThemeData theme) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: theme.colorScheme.outlineVariant,
    );
  }

  Widget _buildControls(AppLocalizations l10n, GpsRecorder recorder) {
    if (recorder.isIdle) {
      return FilledButton.icon(
        onPressed: _starting ? null : _start,
        icon: _starting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.fiber_manual_record, color: Colors.red),
        label: Text(l10n.startRecordingButton),
      );
    }

    // While actively recording, pausing is the single control - saving and
    // resetting deliberately require pausing first, so neither can be fat-
    // fingered mid-ride.
    if (!recorder.isPaused) {
      return FloatingActionButton.extended(
        heroTag: 'recordPauseResume',
        onPressed: recorder.pause,
        icon: const Icon(Icons.pause),
        label: Text(l10n.pauseRecordingButton),
      );
    }

    // Paused: resume, save the ride so far (session keeps going - see
    // _saveRecording), or reset to zero (confirmation only if unsaved -
    // see _resetRecording).
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: 'recordPauseResume',
          tooltip: l10n.resumeRecordingButton,
          onPressed: recorder.resume,
          child: const Icon(Icons.play_arrow),
        ),
        const SizedBox(width: 16),
        FilledButton.icon(
          onPressed: _saving ? null : _saveRecording,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(l10n.save),
        ),
        const SizedBox(width: 16),
        FloatingActionButton(
          heroTag: 'recordReset',
          tooltip: l10n.resetRecordingButton,
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          onPressed: _saving ? null : _resetRecording,
          child: Icon(
            Icons.restart_alt,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
        ),
      ],
    );
  }

  Widget _buildMap() {
    final recorder = context.watch<GpsRecorder>();
    final vehicleIcon = context.watch<VehicleIconController>().option;
    final points = recorder.points;
    final style = _mapStyle;
    final markerSize = vehicleMarkerSize(vehicleIcon);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentLocation ?? kUnknownLocationMapCenter,
        initialZoom: 16,
      ),
      children: [
        TileLayer(
          key: ValueKey(style.id),
          urlTemplate: style.urlTemplate,
          subdomains: style.subdomains,
          tileProvider: createRideAtlasTileProvider(),
          maxNativeZoom: style.maxNativeZoom,
          evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
        ),
        if (_referencePolylines.isNotEmpty)
          PolylineLayer(polylines: _referencePolylines),
        if (points.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [for (final p in points) p.latLng],
                strokeWidth: 4,
                color: const Color(0xFFE53935),
              ),
            ],
          ),
        // The marker position updates every animation frame while
        // course-up follow glides the camera (see _markerLocation) - a
        // ValueListenableBuilder keeps those per-frame rebuilds scoped to
        // this one layer instead of re-running the whole screen's build.
        ValueListenableBuilder<LatLng?>(
          valueListenable: _markerLocation,
          builder: (context, markerLocation, _) {
            if (markerLocation == null) return const SizedBox.shrink();
            return MarkerLayer(
              markers: [
                Marker(
                  point: markerLocation,
                  width: markerSize * _coneMarkerScale,
                  height: markerSize * _coneMarkerScale,
                  alignment: Alignment.center,
                  // The actual root cause of the vehicle icon appearing to
                  // point sideways instead of up: flutter_map's Marker
                  // defaults to rotate:false, which means it rotates *with*
                  // the map's own content (tiles, roads) instead of staying
                  // screen-fixed. Since the map is deliberately rotated to
                  // keep the direction of travel pointing up (course-up), an
                  // embedded marker was being dragged along by that same
                  // rotation instead of staying upright - counter-rotating
                  // it is what actually keeps it pointing up regardless of
                  // the map's current rotation.
                  rotate: true,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // MotionX-GPS-style translucent "cone of light"
                      // showing the GPS heading. The map itself already
                      // turns to keep the direction of travel pointing up
                      // (course-up), so the cone always points straight up
                      // too.
                      if (_currentHeading != null)
                        HeadingCone(
                          size: markerSize * _coneMarkerScale,
                          color: const Color(0xFFFFA726),
                        ),
                      // Always points straight up: the map itself rotates
                      // to keep the direction of travel pointing up.
                      SizedBox(
                        width: markerSize,
                        height: markerSize,
                        child: buildVehicleMarker(vehicleIcon),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        RichAttributionWidget(
          attributions: [TextSourceAttribution(style.attribution)],
        ),
      ],
    );
  }
}

/// One row of the map page's stacked duration/distance/altitude box - label
/// on the left, value on the right, both on one line.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Label on top, value centered below - reads more clearly than the old
    // label-left/value-right row, especially once the mini stats row got
    // its own full-width strip (see _buildMiniStatsRow) with room to spare.
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  return h > 0
      ? '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
      : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// Groups a flat list into consecutive pairs, a trailing odd one out kept
/// as a single-element group - used to lay the live info page's stat cards
/// out two-per-row regardless of how many are currently visible.
List<List<LiveStatKey>> _pairUp(List<LiveStatKey> keys) {
  final rows = <List<LiveStatKey>>[];
  for (var i = 0; i < keys.length; i += 2) {
    rows.add(
      i + 1 < keys.length ? [keys[i], keys[i + 1]] : [keys[i]],
    );
  }
  return rows;
}

/// Wraps [_liveStatCard] so a rider can press-and-hold a card and drag it
/// onto another to swap their positions, right on this screen - the phone
/// home-screen icon-rearranging gesture riders already know, rather than
/// only being able to reorder from a separate settings screen.
Widget _draggableStatCard(
  LiveStatKey key,
  LiveStatsLayoutController layoutController,
  AppLocalizations l10n,
  GpsRecorder recorder,
  SpeedStats speedStats,
  ({double gain, double loss}) elevationChange,
  double? altitude,
  double? maxAltitude,
  double? minAltitude,
  Color accent,
) {
  final card = _liveStatCard(
    key,
    l10n,
    recorder,
    speedStats,
    elevationChange,
    altitude,
    maxAltitude,
    minAltitude,
    accent,
  );
  return LayoutBuilder(
    builder: (context, constraints) {
      return LongPressDraggable<LiveStatKey>(
        data: key,
        delay: const Duration(milliseconds: 350),
        // Matches the cell's own size so the floating copy doesn't jump
        // to some arbitrary width mid-drag.
        feedback: SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: Material(
            color: Colors.transparent,
            child: Opacity(opacity: 0.9, child: card),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.25, child: card),
        child: DragTarget<LiveStatKey>(
          onWillAcceptWithDetails: (details) => details.data != key,
          onAcceptWithDetails: (details) =>
              layoutController.swap(details.data, key),
          builder: (context, candidateData, rejectedData) {
            if (candidateData.isEmpty) return card;
            return DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accent, width: 2),
              ),
              child: card,
            );
          },
        ),
      );
    },
  );
}

/// Builds the [AnalysisStatCard] for a single stat on the live info page -
/// the icon/label come from [liveStatIcon]/[liveStatLabel], only the value
/// string depends on the current recording state.
Widget _liveStatCard(
  LiveStatKey key,
  AppLocalizations l10n,
  GpsRecorder recorder,
  SpeedStats speedStats,
  ({double gain, double loss}) elevationChange,
  double? altitude,
  double? maxAltitude,
  double? minAltitude,
  Color accent,
) {
  final String value;
  switch (key) {
    case LiveStatKey.ridingDuration:
      value = _formatDuration(recorder.elapsed);
    case LiveStatKey.distance:
      value = '${recorder.distanceKm.toStringAsFixed(2)} km';
    case LiveStatKey.restDuration:
      value = _formatDuration(recorder.restDuration);
    case LiveStatKey.currentAltitude:
      value = altitude == null ? '—' : '${altitude.round()} m';
    case LiveStatKey.maxAltitude:
      value = maxAltitude == null ? '—' : '${maxAltitude.round()} m';
    case LiveStatKey.minAltitude:
      value = minAltitude == null ? '—' : '${minAltitude.round()} m';
    case LiveStatKey.timeSinceLastRest:
      value = recorder.timeSinceLastRest == null
          ? '—'
          : _formatDuration(recorder.timeSinceLastRest!);
    case LiveStatKey.averageSpeed:
      value = speedStats.averageMovingKmh == null
          ? '—'
          : '${speedStats.averageMovingKmh!.toStringAsFixed(1)} km/h';
    case LiveStatKey.maxSpeed:
      value = speedStats.maxKmh == null
          ? '—'
          : '${speedStats.maxKmh!.toStringAsFixed(1)} km/h';
    case LiveStatKey.climb:
      value = '${elevationChange.gain.round()} m';
    case LiveStatKey.descent:
      value = '${elevationChange.loss.round()} m';
  }
  return AnalysisStatCard(
    icon: liveStatIcon(key),
    label: liveStatLabel(key, l10n),
    value: value,
    accentColor: accent,
    large: true,
  );
}

/// The info page's full-screen backdrop: a slowly breathing gradient plus
/// two soft glow blobs, replacing the plain theme background so the page
/// reads as a modern dashboard rather than a flat list of colored boxes.
/// Driven by [animation] (a looping 0..1 controller owned by the screen),
/// kept subtle and slow on purpose - this is glanced at while riding, not
/// something that should demand attention.
class _InfoPageBackground extends StatelessWidget {
  const _InfoPageBackground({required this.animation});

  final Animation<double> animation;

  // Fixed blue/white glow colors rather than the theme's own primary/
  // secondary - see [_RecordScreenState._infoAccent] for why: the app's
  // red seed color renders as pink/maroon in dark mode, which is the
  // "lunapark" look this whole page moved away from.
  static const _glowBlue = Color(0xFF4FA3FF);
  static const _glowWhite = Color(0xFFCFE8FF);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        return Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.lerp(
                    Alignment.topLeft,
                    Alignment.topRight,
                    t,
                  )!,
                  end: Alignment.lerp(
                    Alignment.bottomRight,
                    Alignment.bottomLeft,
                    t,
                  )!,
                  colors: dark
                      ? const [
                          Color(0xFF0A0E1C),
                          Color(0xFF0F2038),
                          Color(0xFF090C14),
                        ]
                      : const [
                          Color(0xFFE8F2FF),
                          Color(0xFFEFF6FF),
                          Color(0xFFFFFFFF),
                        ],
                ),
              ),
            ),
            Positioned(
              top: -100 + 20 * t,
              left: -80,
              child: _GlowBlob(
                color: _glowBlue,
                size: 280,
                opacity: (dark ? 0.28 : 0.18) + 0.08 * t,
              ),
            ),
            Positioned(
              bottom: -120,
              right: -90 + 20 * t,
              child: _GlowBlob(
                color: _glowWhite,
                size: 320,
                opacity: (dark ? 0.16 : 0.20) + 0.05 * (1 - t),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A large, soft-edged radial glow used by [_InfoPageBackground] - fades to
/// fully transparent at its own edge, so it reads as diffuse light rather
/// than a hard-edged circle.
class _GlowBlob extends StatelessWidget {
  const _GlowBlob({
    required this.color,
    required this.size,
    required this.opacity,
  });

  final Color color;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      elevation: 2,
      child: IconButton(
        icon: Icon(icon),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}

/// Smoothly animates [value] toward each new reading instead of snapping
/// straight to it, so a number fed by GPS fixes that only arrive roughly
/// once a second (the fastest a phone's GPS chip realistically produces
/// them) still reads as continuously live rather than static-then-jump.
/// [duration] is chosen close to that update cadence, so one animation is
/// just finishing as the next fix retargets it - this doesn't make the
/// underlying data any fresher, but it removes the "did it freeze?" feel
/// of a value sitting motionless for the better part of a second.
class _AnimatedNumber extends StatefulWidget {
  const _AnimatedNumber({required this.value, required this.builder});

  final double value;
  final Widget Function(BuildContext context, double value) builder;

  @override
  State<_AnimatedNumber> createState() => _AnimatedNumberState();
}

class _AnimatedNumberState extends State<_AnimatedNumber>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 900);

  late final AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration);
    _animation = AlwaysStoppedAnimation(widget.value);
  }

  @override
  void didUpdateWidget(covariant _AnimatedNumber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _animation =
          Tween<double>(begin: _animation.value, end: widget.value).animate(
            CurvedAnimation(parent: _controller, curve: Curves.linear),
          );
      _controller
        ..stop()
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => widget.builder(context, _animation.value),
    );
  }
}
