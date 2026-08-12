import 'dart:async';
import 'dart:convert';

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
import '../repositories/live_stats_layout_controller.dart';
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
import 'analysis_sheet.dart' show AnalysisStatCard;
import 'location_picker_screen.dart';
import 'map_screen.dart' show RouteMapScreen;
import 'ride_photo_picker_screen.dart';

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
      // Close to the ~1s cadence real GPS fixes arrive at (a phone's GPS
      // chip realistically can't produce fixes much faster than that) -
      // long enough that one camera animation is still finishing when the
      // next fix retargets it, so the map is continuously gliding/turning
      // instead of snapping into place and sitting still for most of each
      // second.
      duration: const Duration(milliseconds: 950),
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
      _mapController.moveAndRotate(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoom,
        rotationTween.evaluate(animation),
      );
    }

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
                  // Was 5s - far too slow for a course-up map to track real
                  // turns/heading changes without visibly lagging behind
                  // the actual road. 1s matches what a normal navigation
                  // app polls at.
                  intervalDuration: const Duration(seconds: 1),
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
            // Position and rotation animate together over the same
            // duration - see _animateCameraTo - rather than the map
            // snapping to the new spot and then separately swinging to
            // the new heading.
            _animateCameraTo(location: location, heading: heading);
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
                        icon: Icons.map_outlined,
                        tooltip: l10n.recordMapTabTooltip,
                        onPressed: _switchToMap,
                      ),
                    ],
                  ),
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
