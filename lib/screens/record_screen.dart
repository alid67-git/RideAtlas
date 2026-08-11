import 'dart:async';
import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/base_map_style.dart';
import '../models/gpx_route.dart';
import '../models/track_point.dart';
import '../repositories/photo_repository.dart';
import '../repositories/route_repository.dart';
import '../repositories/vehicle_icon_controller.dart';
import '../services/battery_info.dart';
import '../services/battery_optimization.dart';
import '../services/gallery_scan.dart';
import '../services/gps_recorder.dart';
import '../services/gpx_parser.dart';
import '../services/track_io.dart';
import '../widgets/heading_cone.dart';
import '../widgets/recording_indicator.dart';
import '../widgets/satellite_count_badge.dart';
import '../widgets/vehicle_marker.dart';
import 'analysis_sheet.dart'
    show AnalysisElevationChart, AnalysisStatCard, AnalysisStatGrid;
import 'location_picker_screen.dart';
import 'map_screen.dart' show RouteMapScreen;
import 'ride_photo_picker_screen.dart';

const _speedDistance = Distance();

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
  const RecordScreen({super.key});

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
  /// page's header.
  bool _showMap = false;

  GpsRecorder get _recorder => context.read<GpsRecorder>();

  /// The device's live position, tracked independently of [GpsRecorder] and
  /// kept running for the entire lifetime of this screen (idle and
  /// recording alike) - this is the map's one and only source of truth for
  /// "where am I". It's tempting to switch to the recorder's own points once
  /// recording starts (that's a second, separate GPS subscription
  /// [GpsRecorder] owns for the actual track), but doing that caused a
  /// visible jump: a freshly-started stream's first fix can be a quick,
  /// less-accurate cached location before it settles, which reads as
  /// "teleporting" right when recording begins. Keeping one continuous
  /// stream driving the map avoids that, at the minor cost of two GPS
  /// subscriptions running at once while recording.
  StreamSubscription<Position>? _liveLocationSub;
  LatLng? _currentLocation;
  bool _centeredOnce = false;

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

  late final StreamSubscription<MapEvent> _mapEventSub;

  @override
  void initState() {
    super.initState();
    recordScreenVisible.value = true;
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat(reverse: true);
    _startLiveLocation();
    _mapEventSub = _mapController.mapEventStream.listen((event) {
      if (event.source != MapEventSource.mapController && _followMe) {
        setState(() => _followMe = false);
      }
    });
    // Refreshes the elapsed-time label even between GPS fixes.
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _recorder.isRecording) setState(() {});
    });
  }

  /// Switches from the info page to the map, and immediately re-syncs the
  /// map to the current position/heading rather than waiting for the next
  /// GPS fix (which can be several seconds away) - the map widget is torn
  /// down while the info page is showing, so it would otherwise briefly
  /// reappear wherever it last was instead of already being correct.
  void _switchToMap() {
    setState(() => _showMap = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final location = _currentLocation;
      if (location != null && _followMe) {
        _mapController.move(location, _mapController.camera.zoom);
      }
      final heading = _currentHeading;
      if (heading != null && _followMe) _mapController.rotate(heading);
    });
  }

  /// Recenters and resumes following the live position, course-up. A repeat
  /// tap while already following is a no-op - there's nothing further to
  /// switch to.
  void _recenter() {
    if (_followMe) return;
    final location = _currentLocation;
    setState(() => _followMe = true);
    if (location != null) {
      final zoom = _mapController.camera.zoom;
      _mapController.move(location, zoom < 15 ? 16 : zoom);
    }
    _applyRotation();
  }

  /// Rotates the map to the live heading (course-up), if known yet.
  void _applyRotation() {
    final heading = _currentHeading;
    if (heading != null) _rotateMapTo(heading);
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

  /// Animates the map's rotation to [targetHeading] instead of snapping
  /// instantly, taking the shorter way round (e.g. 350deg -> 10deg animates
  /// as +20, not -340) - reads the map's actual current rotation each call
  /// rather than tracking a separate copy of it, so this can't drift out of
  /// sync with the map itself.
  void _rotateMapTo(double targetHeading) {
    final current = _mapController.camera.rotation;
    var delta = (targetHeading - current) % 360;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    if (delta.abs() < 0.5) return;
    final target = current + delta;
    final animation = Tween<double>(begin: current, end: target).animate(
      CurvedAnimation(parent: _rotationController, curve: Curves.easeOut),
    );
    void listener() => _mapController.rotate(animation.value);
    animation.addListener(listener);
    _rotationController
      ..stop()
      ..reset();
    _rotationController.forward().whenComplete(() {
      animation.removeListener(listener);
    });
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
                  intervalDuration: const Duration(seconds: 5),
                )
              : const LocationSettings(
                  accuracy: LocationAccuracy.high,
                  distanceFilter: 5,
                ),
        ).listen((pos) {
          if (!mounted) return;
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
            _mapController.move(location, 16);
          } else if (_followMe) {
            _mapController.move(location, _mapController.camera.zoom);
          }
          if (_followMe && heading != null) {
            _rotateMapTo(heading);
          }
        });
  }

  @override
  void dispose() {
    recordScreenVisible.value = false;
    _tickTimer?.cancel();
    _liveLocationSub?.cancel();
    _mapEventSub.cancel();
    _rotationController.dispose();
    _bgController.dispose();
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
    // Recording always starts with the vehicle centered on screen, even if
    // the map had been panned away from it beforehand.
    final location = _currentLocation;
    setState(() {
      _followMe = true;
      // Opens on the info page - the map is one tap away via its toggle
      // button - rather than whatever page the rider happened to be
      // looking at before tapping start.
      _showMap = false;
    });
    if (location != null) _mapController.move(location, 16);
    _applyRotation();
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

  Future<bool> _confirmDiscard() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.discardRecordingConfirmTitle),
        content: Text(l10n.discardRecordingConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.discardRecordingButton),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _discard() async {
    if (await _confirmDiscard() && mounted) {
      await _recorder.discard();
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _finish() async {
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
    // Read before stop() - it resets GpsRecorder back to idle, taking
    // startedAt with it.
    final recordingStart = _recorder.startedAt;
    final points = await _recorder.stop();
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
    );
    if (!mounted) return;
    if (recordingStart != null) {
      await _offerGalleryMedia(route, recordingStart);
      if (!mounted) return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => RouteMapScreen(routeId: route.id)),
    );
  }

  /// Looks for photos/videos the gallery gained during this ride and, if
  /// any turn up, lets the rider pick which to attach - added with their
  /// own EXIF/gallery GPS tag if they have one, or by asking where to place
  /// them on the map otherwise (same fallback as adding media by hand from
  /// the route screen). Never blocks saving the ride: any failure here
  /// (permission refused, nothing found, plugin error) is swallowed and the
  /// recording is still saved either way.
  Future<void> _offerGalleryMedia(GpxRoute route, DateTime recordingStart) async {
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
      // AssetEntity's own LatLng type isn't the one the rest of the app
      // uses (latlong2) - pull the raw doubles out immediately rather than
      // holding onto it, so there's no ambiguity between the two.
      final assetLocation = await asset.latlngAsync();
      var lat = assetLocation?.latitude;
      var lng = assetLocation?.longitude;
      if (lat == null || lng == null || (lat == 0 && lng == 0)) {
        final picked = await _pickLocationManually(route);
        if (!mounted) return;
        lat = picked?.latitude;
        lng = picked?.longitude;
      }
      final file = await asset.originFile ?? await asset.file;
      if (file == null) continue;
      final fileBytes = await file.readAsBytes();
      await photoRepo.add(
        routeId: route.id,
        bytes: fileBytes,
        lat: lat,
        lng: lng,
        type: candidate.mediaType,
      );
    }
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
    if (!recorder.isIdle && !_showMap) {
      return _buildInfoPage(context, recorder);
    }
    return _buildMapPage(context, recorder);
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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RoundIconButton(
                      icon: Icons.arrow_back,
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _buildStats(context, l10n, recorder)),
                    const SizedBox(width: 8),
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: SatelliteCountBadge(),
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
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 100,
            child: SafeArea(
              top: false,
              child: FloatingActionButton.small(
                heroTag: 'recordRecenter',
                tooltip: l10n.recenterTooltip,
                backgroundColor: _followMe
                    ? Theme.of(context).colorScheme.primary
                    : null,
                foregroundColor: _followMe
                    ? Theme.of(context).colorScheme.onPrimary
                    : null,
                onPressed: _currentLocation == null ? null : _recenter,
                // A compass-needle icon while auto-following (course-up),
                // the plain dot otherwise - the same visual language most
                // map/nav apps use for this.
                child: Icon(
                  _followMe ? Icons.navigation : Icons.my_location,
                ),
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

    final durationStr = _formatDuration(recorder.elapsed);
    final altitude = recorder.currentAltitude;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // IntrinsicHeight resolves the height both boxes stretch to before
        // laying them out - without it, CrossAxisAlignment.stretch here asks
        // the Row to be as tall as its own children while also stretching
        // those children to the Row's height, a circular size dependency
        // that made this whole section silently fail to lay out at all
        // (the top bar rendered with nothing in it, next to the back
        // button) because this Row sits inside a Positioned with no bottom
        // edge, which leaves incoming height constraints unbounded.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The current speed is the one number a rider actually needs to
              // read at a glance while moving, so it gets its own big display;
              // everything else is secondary and stays small.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 6),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // At least double the old headlineMedium size - this is
                    // the number a rider needs to read at a glance while
                    // moving, the old size was too small for that.
                    Text(
                      recorder.currentSpeedKmh.toStringAsFixed(0),
                      style: const TextStyle(
                        fontSize: 62,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                    Text(
                      l10n.speedLabel,
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Three stacked rows instead of three side-by-side columns -
              // each gets the box's full width to itself, so label+value
              // never has to compete for horizontal space with its
              // neighbors the way the old 3-column layout did.
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 6),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: _StatRow(
                          label: l10n.duration,
                          value: durationStr,
                        ),
                      ),
                      _statDividerHorizontal(theme),
                      Expanded(
                        child: _StatRow(
                          label: l10n.distance,
                          value:
                              '${recorder.distanceKm.toStringAsFixed(2)} km',
                        ),
                      ),
                      _statDividerHorizontal(theme),
                      Expanded(
                        child: _StatRow(
                          label: l10n.currentAltitudeLabel,
                          value: altitude == null
                              ? '—'
                              : '${altitude.round()} m',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (recorder.isAutoPaused) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 6),
              ],
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
        ],
      ],
    );
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0
        ? '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
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
    final speedSpots = _speedTimeSpots(points);
    final altitude = recorder.currentAltitude;
    final hasSpeedChart = speedSpots.length >= 2;
    final hasElevationChart = elevationSamples.length >= 2;
    final accent = _cardAccent(theme);

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
                        icon: Icons.map_outlined,
                        tooltip: l10n.recordMapTabTooltip,
                        onPressed: _switchToMap,
                      ),
                    ],
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
                  child: SingleChildScrollView(
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
                              Text(
                                recorder.currentSpeedKmh.toStringAsFixed(0),
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
                        Row(
                          children: [
                            Expanded(
                              child: _DurationTile(
                                icon: Icons.timer_outlined,
                                label: l10n.netDurationLabel,
                                value: _formatDuration(recorder.elapsed),
                                color: accent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _DurationTile(
                                icon: Icons.schedule,
                                label: l10n.totalDurationLabel,
                                value: _formatDuration(
                                  recorder.totalDuration ?? Duration.zero,
                                ),
                                color: accent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        AnalysisStatGrid(
                          childAspectRatio: 2.3,
                          children: [
                            AnalysisStatCard(
                              icon: Icons.route,
                              label: l10n.distance,
                              value:
                                  '${recorder.distanceKm.toStringAsFixed(2)} km',
                              accentColor: accent,
                              large: true,
                            ),
                            AnalysisStatCard(
                              icon: Icons.pause_circle_outline,
                              label: l10n.restDurationLabel,
                              value: _formatDuration(recorder.restDuration),
                              accentColor: accent,
                              large: true,
                            ),
                            AnalysisStatCard(
                              icon: Icons.equalizer,
                              label: l10n.averageSpeedLabel,
                              value: speedStats.averageMovingKmh == null
                                  ? '—'
                                  : '${speedStats.averageMovingKmh!.toStringAsFixed(1)} km/h',
                              accentColor: accent,
                              large: true,
                            ),
                            AnalysisStatCard(
                              icon: Icons.bolt,
                              label: l10n.maxSpeed,
                              value: speedStats.maxKmh == null
                                  ? '—'
                                  : '${speedStats.maxKmh!.toStringAsFixed(1)} km/h',
                              accentColor: accent,
                              large: true,
                            ),
                            AnalysisStatCard(
                              icon: Icons.terrain,
                              label: l10n.currentAltitudeLabel,
                              value: altitude == null
                                  ? '—'
                                  : '${altitude.round()} m',
                              accentColor: accent,
                              large: true,
                            ),
                            AnalysisStatCard(
                              icon: Icons.trending_up,
                              label: l10n.climb,
                              value: '${elevationChange.gain.round()} m',
                              accentColor: accent,
                              large: true,
                            ),
                            AnalysisStatCard(
                              icon: Icons.trending_down,
                              label: l10n.descent,
                              value: '${elevationChange.loss.round()} m',
                              accentColor: accent,
                              large: true,
                            ),
                          ],
                        ),
                        if (hasSpeedChart || hasElevationChart) ...[
                          const SizedBox(height: 8),
                          // Fixed height rather than Expanded - this whole
                          // section now lives inside a SingleChildScrollView
                          // (needed once the stat cards above grew this
                          // much), and a scroll view can't hand out
                          // unbounded height the way the old Expanded did.
                          SizedBox(
                            height: 160,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (hasSpeedChart)
                                  Expanded(
                                    child: _MiniChart(
                                      icon: Icons.speed,
                                      title: l10n.speedChartTitle,
                                      child: _SpeedTimeChart(
                                        spots: speedSpots,
                                        accent: accent,
                                      ),
                                    ),
                                  ),
                                if (hasSpeedChart && hasElevationChart)
                                  const SizedBox(width: 8),
                                if (hasElevationChart)
                                  Expanded(
                                    child: _MiniChart(
                                      icon: Icons.terrain,
                                      title: l10n.elevationChartTitle,
                                      child: AnalysisElevationChart(
                                        samples: elevationSamples,
                                        showPeakMarkers: true,
                                        lineColor: accent,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
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

  /// Per-segment speed samples (minutes since the first *moving* sample,
  /// km/h) for the speed-over-time chart, using the same plausibility
  /// filter [buildSpeedStats] does (ignores stopped/GPS-jitter and
  /// implausible spikes) so the chart and the max/average speed stats above
  /// it always agree. Downsampled to a bounded point count so the chart
  /// stays cheap to rebuild every second even on a multi-hour ride.
  List<FlSpot> _speedTimeSpots(List<TrackPoint> points) {
    const minMovingKmh = 1.0;
    const maxPlausibleKmh = 250.0;
    const maxAccelerationKmhPerSec = 30.0;
    if (points.length < 2) return const [];

    final spots = <FlSpot>[];
    double? lastAcceptedKmh;
    DateTime? lastAcceptedTime;
    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final t0 = prev.time;
      final t1 = curr.time;
      if (t0 == null || t1 == null) continue;
      final dtSeconds = t1.difference(t0).inMilliseconds / 1000.0;
      if (dtSeconds < 1) continue;
      final meters = _speedDistance(prev.latLng, curr.latLng);
      final kmh = (meters / 1000.0) / (dtSeconds / 3600.0);
      if (kmh < minMovingKmh || kmh > maxPlausibleKmh) continue;
      // Same GPS-glitch guard as buildSpeedStats - a segment implying
      // implausible acceleration since the last accepted reading is a bad
      // fix, not real riding.
      if (lastAcceptedKmh != null && lastAcceptedTime != null) {
        final accelDtSeconds =
            t1.difference(lastAcceptedTime).inMilliseconds / 1000.0;
        if (accelDtSeconds > 0 &&
            (kmh - lastAcceptedKmh).abs() >
                maxAccelerationKmhPerSec * accelDtSeconds) {
          continue;
        }
      }
      lastAcceptedKmh = kmh;
      lastAcceptedTime = t1;
      // Minutes since t1 for now - shifted below once the first accepted
      // sample's own time is known, so the chart starts right where actual
      // riding does instead of at whenever recording began. A ride that
      // sits still (or in a pre-departure rest) for a few minutes before
      // moving used to leave a blank, meaningless stretch at the start of
      // this exact chart.
      spots.add(FlSpot(t1.millisecondsSinceEpoch / 60000.0, kmh));
    }
    if (spots.isEmpty) return spots;
    final offset = spots.first.x;
    for (var i = 0; i < spots.length; i++) {
      spots[i] = FlSpot(spots[i].x - offset, spots[i].y);
    }

    const maxChartPoints = 200;
    if (spots.length <= maxChartPoints) return spots;
    final step = (spots.length / maxChartPoints).ceil();
    return [for (var i = 0; i < spots.length; i += step) spots[i]];
  }

  /// Thin vertical separator between the duration/distance/altitude
  /// columns, so their values read as distinct fields instead of running
  /// into each other on narrow screens.
  /// Thin horizontal separator between the stacked duration/distance/
  /// altitude rows in the map page's header.
  Widget _statDividerHorizontal(ThemeData theme) {
    return Container(height: 1, color: theme.colorScheme.outlineVariant);
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

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: 'recordPauseResume',
          onPressed: recorder.isPaused ? recorder.resume : recorder.pause,
          child: Icon(recorder.isPaused ? Icons.play_arrow : Icons.pause),
        ),
        const SizedBox(width: 16),
        FilledButton.icon(
          onPressed: _saving ? null : _finish,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: Text(l10n.finishRecordingButton),
        ),
        const SizedBox(width: 16),
        FloatingActionButton(
          heroTag: 'recordDiscard',
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          onPressed: _saving ? null : _discard,
          child: Icon(
            Icons.delete_outline,
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
    final style = kBaseMapStyles.first;
    final markerSize = vehicleMarkerSize(vehicleIcon);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentLocation ?? const LatLng(41.0082, 28.9784),
        initialZoom: 16,
      ),
      children: [
        TileLayer(
          urlTemplate: style.urlTemplate,
          subdomains: style.subdomains,
          userAgentPackageName: 'com.rideatlas.app',
          maxNativeZoom: 20,
        ),
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
        if (_currentLocation != null)
          MarkerLayer(
            markers: [
              Marker(
                point: _currentLocation!,
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
                // rotation instead of staying upright - counter-rotating it
                // is what actually keeps it pointing up regardless of the
                // map's current rotation.
                rotate: true,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // MotionX-GPS-style translucent "cone of light" showing
                    // the GPS heading. The map itself already turns to keep
                    // the direction of travel pointing up (course-up), so
                    // the cone always points straight up too.
                    if (_currentHeading != null)
                      HeadingCone(
                        size: markerSize * _coneMarkerScale,
                        color: const Color(0xFFFFA726),
                      ),
                    // Always points straight up: the map itself rotates to
                    // keep the direction of travel pointing up.
                    SizedBox(
                      width: markerSize,
                      height: markerSize,
                      child: buildVehicleMarker(vehicleIcon),
                    ),
                  ],
                ),
              ),
            ],
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
    return Row(
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
        const Spacer(),
        // At least double the old titleSmall size - readable at a glance
        // while riding was the whole point of this box.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

/// One of the two prominent duration readouts under the hero speed number
/// on [RecordScreen]'s info page (active riding time / total time). Shares
/// the same single accent color and glass/border treatment as
/// [AnalysisStatCard] below it, differentiated only by icon and label.
class _DurationTile extends StatelessWidget {
  const _DurationTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.20 : 0.12,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 2),
          FittedBox(
            child: Text(
              value,
              maxLines: 1,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

/// Wraps a chart with a small colored title, for the side-by-side speed/
/// elevation charts at the bottom of the info page.
class _MiniChart extends StatelessWidget {
  const _MiniChart({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: _RecordScreenState._infoAccent),
            const SizedBox(width: 4),
            Text(title, style: theme.textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(child: child),
      ],
    );
  }
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

/// Speed-over-time line chart for [RecordScreen]'s info page - same visual
/// language as [AnalysisElevationChart], just plotting km/h against minutes
/// since the ride started instead of elevation against distance.
///
/// The top speed reached always stays marked on the chart itself (a dot
/// plus a small floating label) rather than only being visible by touching
/// the chart - as the ride goes on and the x-axis keeps rescaling to fit
/// more time, the peak would otherwise scroll out of easy reach and there'd
/// be no way to tell "how fast did I actually go" from the chart at a
/// glance.
class _SpeedTimeChart extends StatelessWidget {
  const _SpeedTimeChart({required this.spots, required this.accent});

  final List<FlSpot> spots;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final maxX = spots.last.x;
    final theme = Theme.of(context);

    var maxIndex = 0;
    for (var i = 1; i < spots.length; i++) {
      if (spots[i].y > spots[maxIndex].y) maxIndex = i;
    }
    final maxSpot = spots[maxIndex];

    final barData = LineChartBarData(
      spots: spots,
      isCurved: true,
      barWidth: 2,
      color: accent,
      dotData: FlDotData(
        show: true,
        checkToShowDot: (spot, bar) => spot == maxSpot,
        getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
          radius: 4,
          color: accent,
          strokeWidth: 2,
          strokeColor: theme.colorScheme.surface,
        ),
      ),
      belowBarData: BarAreaData(
        show: true,
        color: accent.withValues(alpha: 0.15),
      ),
    );

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX == 0 ? 1 : maxX,
        minY: 0,
        maxY: maxY + 14,
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, meta) {
                return Text(
                  '${v.round()}',
                  style: theme.textTheme.bodySmall,
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (v, meta) {
                return Text(
                  '${v.round()}dk',
                  style: theme.textTheme.bodySmall,
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          enabled: false,
          touchTooltipData: LineTouchTooltipData(
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 3,
            ),
            tooltipMargin: 8,
            getTooltipColor: (_) => accent.withValues(alpha: 0.92),
            getTooltipItems: (touchedSpots) => touchedSpots
                .map(
                  (s) => LineTooltipItem(
                    '${s.y.round()} km/h',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        showingTooltipIndicators: [
          ShowingTooltipIndicators([LineBarSpot(barData, 0, maxSpot)]),
        ],
        lineBarsData: [barData],
      ),
    );
  }
}
