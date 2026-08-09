import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/base_map_style.dart';
import '../repositories/map_heading_mode_controller.dart';
import '../repositories/route_repository.dart';
import '../repositories/vehicle_icon_controller.dart';
import '../services/battery_info.dart';
import '../services/battery_optimization.dart';
import '../services/gps_recorder.dart';
import '../services/track_io.dart';
import '../widgets/heading_cone.dart';
import '../widgets/recording_indicator.dart';
import '../widgets/satellite_count_badge.dart';
import '../widgets/vehicle_marker.dart';
import 'map_screen.dart' show RouteMapScreen;

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

class _RecordScreenState extends State<RecordScreen> {
  /// How much bigger than the vehicle marker itself the heading cone's
  /// bounding box is, so the cone has room to fan out beyond the icon.
  static const _coneMarkerScale = 2.3;

  final _mapController = MapController();
  Timer? _tickTimer;
  bool _starting = false;
  bool _saving = false;

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

  /// True while the map should keep auto-centering on the live position.
  /// Any user-driven map interaction (drag, pinch, fling, ...) turns this
  /// off, so panning around to look at the surroundings isn't constantly
  /// fought by the auto-follow; the recenter button turns it back on - and,
  /// if it's tapped again while already following, toggles [_headingUp]
  /// instead (see [_recenter]).
  bool _followMe = true;

  /// False: north is always up, map never rotates on its own - the
  /// translucent heading cone (see [HeadingCone]) rotates instead to show
  /// which way the rider is facing. True (default, like a normal navigation
  /// app): the map rotates to keep the direction of travel pointing up
  /// (course-up), so the cone stays fixed pointing "forward" instead.
  /// Seeded from, and kept in sync with, [MapHeadingModeController] so the
  /// choice persists across recordings instead of resetting every time.
  bool _headingUp = true;

  late final StreamSubscription<MapEvent> _mapEventSub;

  @override
  void initState() {
    super.initState();
    recordScreenVisible.value = true;
    _headingUp = context.read<MapHeadingModeController>().headingUp;
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

  /// Recenters and resumes following the live position - unless the map is
  /// already following it, in which case a repeat tap instead switches
  /// between north-up and course-up (see [_headingUp]).
  void _recenter() {
    if (_followMe) {
      setState(() => _headingUp = !_headingUp);
      context.read<MapHeadingModeController>().setHeadingUp(_headingUp);
      _applyRotation();
      return;
    }
    final location = _currentLocation;
    setState(() => _followMe = true);
    if (location != null) {
      final zoom = _mapController.camera.zoom;
      _mapController.move(location, zoom < 15 ? 16 : zoom);
    }
    _applyRotation();
  }

  /// Rotates the map to match [_headingUp]'s current mode - north-up
  /// (rotation 0) or course-up (rotation = live heading, if known yet).
  void _applyRotation() {
    if (!_headingUp) {
      _mapController.rotate(0);
      return;
    }
    final heading = _currentHeading;
    if (heading != null) _mapController.rotate(heading);
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
          // map twitch around when stopped.
          final heading = (pos.heading >= 0 && pos.speed > 0.5)
              ? pos.heading
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
          if (_followMe && _headingUp && heading != null) {
            _mapController.rotate(heading);
          }
        });
  }

  @override
  void dispose() {
    recordScreenVisible.value = false;
    _tickTimer?.cancel();
    _liveLocationSub?.cancel();
    _mapEventSub.cancel();
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
    setState(() => _followMe = true);
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
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => RouteMapScreen(routeId: route.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final recorder = context.watch<GpsRecorder>();

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
                // A compass-needle icon while following the direction of
                // travel (course-up), the plain dot while north stays up -
                // the same visual language most map/nav apps use for this.
                child: Icon(
                  _followMe && _headingUp
                      ? Icons.navigation
                      : Icons.my_location,
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

    final d = recorder.elapsed;
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    final durationStr = h > 0
        ? '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
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
                  horizontal: 14,
                  vertical: 6,
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
                    Text(
                      recorder.currentSpeedKmh.toStringAsFixed(0),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                    Text(l10n.speedLabel, style: theme.textTheme.labelSmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 6),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _StatColumn(label: l10n.duration, value: durationStr),
                      _StatColumn(
                        label: l10n.distance,
                        value: '${recorder.distanceKm.toStringAsFixed(2)} km',
                      ),
                      _StatColumn(
                        label: l10n.currentAltitudeLabel,
                        value: altitude == null ? '—' : '${altitude.round()} m',
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
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // MotionX-GPS-style translucent "cone of light" showing
                    // the GPS heading. Rotated to point up in course-up
                    // mode (where the map itself already turned to put the
                    // heading up), or to the actual compass heading in
                    // north-up mode (where the map stays fixed, so the cone
                    // is the only thing that shows direction of travel).
                    if (_currentHeading != null)
                      Transform.rotate(
                        angle: _headingUp
                            ? 0
                            : _currentHeading! * math.pi / 180,
                        child: HeadingCone(
                          size: markerSize * _coneMarkerScale,
                          color: const Color(0xFFFFA726),
                        ),
                      ),
                    // Always points straight up, regardless of north-up vs.
                    // course-up mode: in course-up mode that's because the
                    // map itself rotates to keep the direction of travel
                    // pointing up, and in north-up mode it's simply the
                    // app's chosen vehicle icon, not a compass needle.
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

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: theme.textTheme.titleSmall),
        Text(label, style: theme.textTheme.labelSmall),
      ],
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
