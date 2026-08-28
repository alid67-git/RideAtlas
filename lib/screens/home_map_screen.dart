import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../build_info.dart';
import '../l10n/gen/app_localizations.dart';
import '../models/base_map_style.dart';
import '../repositories/daily_mode_controller.dart';
import '../repositories/route_repository.dart';
import '../repositories/vehicle_icon_controller.dart';
import '../services/app_update_controller.dart';
import '../services/daily_recording_coordinator.dart';
import '../services/gps_recorder.dart';
import '../services/live_location.dart';
import '../services/native_recording.dart';
import '../widgets/app_update_ui.dart';
import '../widgets/recording_indicator.dart';
import '../widgets/satellite_count_badge.dart';
import '../widgets/vehicle_marker.dart';
import 'map_screen.dart' show MapStylePickerDialog;
import 'record_screen.dart';
import 'route_list_screen.dart';
import 'settings_screen.dart';

const _metaBoxName = 'rideatlas_meta';
const _mapStyleKey = 'base_map_style_id';
const _lastSeenBuildKey = 'last_seen_build';

/// A wide, regional view (several countries visible) - the landing map
/// starts here and stays here even once the device's location is found;
/// only an explicit "locate me" tap zooms in close.
const _defaultZoom = 5.0;

/// The app's landing screen: a live map centered on the device's current
/// location (like a stock maps app), with the saved-routes list one tap
/// away via the list icon.
class HomeMapScreen extends StatefulWidget {
  const HomeMapScreen({super.key});

  @override
  State<HomeMapScreen> createState() => _HomeMapScreenState();
}

class _HomeMapScreenState extends State<HomeMapScreen> {
  final _mapController = MapController();
  StreamSubscription<Position>? _positionSub;
  LatLng? _currentLocation;
  String? _locationError;
  BaseMapStyle _mapStyle = kBaseMapStyles.first;
  bool _centeredOnce = false;

  /// Brief non-interactive status under the record button (offline / online).
  String? _gpsFlashMessage;
  Timer? _gpsFlashTimer;
  bool _hadGpsFix = false;
  bool _offlineHintShown = false;

  DailyRecordingCoordinator? _dailyCoordinator;
  DailyModeController? _dailyModeListened;

  static const _gpsFlashDuration = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Ensure tiles fetch even if GPS never moves the camera (same center/
      // zoom as MapOptions → flutter_map may skip the first request).
      if (mounted) kickMapTileLayer(_mapController);
      await _maybeShowWhatsNew();
      // After what's-new: check once; offer a single "Güncelle" dialog. The
      // same banner also appears on the recording/info screens via
      // [AppUpdateController].
      if (AppUpdateController.isSupported) {
        final updates = context.read<AppUpdateController>();
        await updates.check();
        if (!mounted) return;
        if (await offerAppUpdateDialog(context)) {
          await installAppUpdate(context);
        }
      }
      // If a fix hasn't arrived yet, tell the user recording would start offline.
      if (!_hadGpsFix && mounted) _showOfflineGpsHint();
      if (NativeRecording.isSupported) await _bootstrapRecordingOnOpen();
    });
    _loadMapStyle();
    _startLocationUpdates();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final daily = context.read<DailyModeController>();
    if (!identical(daily, _dailyModeListened)) {
      _dailyModeListened?.removeListener(_onDailyModeChanged);
      _dailyModeListened = daily;
      _dailyModeListened!.addListener(_onDailyModeChanged);
    }
  }

  void _onDailyModeChanged() {
    final coordinator = _dailyCoordinator;
    if (coordinator == null || !mounted) return;
    final l10n = AppLocalizations.of(context)!;
    coordinator.syncDayWatch(
      l10n: l10n,
      localeLanguageCode: Localizations.localeOf(context).languageCode,
    );
  }

  /// Daily mode: silent resume / day-rollover / auto-start (no Record screen).
  /// Classic mode: interrupted session → Record screen + snackbar.
  Future<void> _bootstrapRecordingOnOpen() async {
    try {
      final recorder = context.read<GpsRecorder>();
      final routes = context.read<RouteRepository>();
      final daily = context.read<DailyModeController>();
      final l10n = AppLocalizations.of(context)!;
      final lang = Localizations.localeOf(context).languageCode;

      _dailyCoordinator?.dispose();
      final coordinator = DailyRecordingCoordinator(
        recorder: recorder,
        routes: routes,
        dailyMode: daily,
      );
      _dailyCoordinator = coordinator;

      final result = await coordinator.onAppOpen(
        l10n: l10n,
        localeLanguageCode: lang,
        openRecordScreen: () async {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.recordingSessionResumed)),
          );
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const RecordScreen(initialShowMap: true),
            ),
          );
        },
      );
      if (!mounted) return;
      if (result == DailyBootstrapResult.needsPermission) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.dailyModeNeedsPermission)),
        );
      }
    } catch (_) {
      // Bridge missing in tests / non-Android - nothing to do.
    }
  }

  void _showGpsFlash(String message) {
    _gpsFlashTimer?.cancel();
    if (!mounted) return;
    setState(() => _gpsFlashMessage = message);
    _gpsFlashTimer = Timer(_gpsFlashDuration, () {
      if (mounted) setState(() => _gpsFlashMessage = null);
    });
  }

  void _showOfflineGpsHint() {
    if (_offlineHintShown || _hadGpsFix || !mounted) return;
    _offlineHintShown = true;
    _showGpsFlash(AppLocalizations.of(context)!.gpsOfflineRecordingHint);
  }

  void _showOnlineGpsFlash(double accuracyMeters) {
    if (!mounted) return;
    final accuracy = accuracyMeters.isFinite && accuracyMeters > 0
        ? accuracyMeters.round().toString()
        : '—';
    _showGpsFlash(AppLocalizations.of(context)!.gpsOnlineStatus(accuracy));
  }

  Future<void> _maybeShowWhatsNew() async {
    final box = await Hive.openBox<String>(_metaBoxName);
    if (box.get(_lastSeenBuildKey) == kAppBuildLabel) return;
    if (!mounted) return;

    final l10n = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(l10n.appRunningVersion(kAppBuildLabel)),
        content: Text(kAppBuildNote),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
    await box.put(_lastSeenBuildKey, kAppBuildLabel);
  }

  Future<void> _loadMapStyle() async {
    final box = await Hive.openBox<String>(_metaBoxName);
    final savedId = box.get(_mapStyleKey);
    if (savedId == null || !mounted) return;
    setState(() => _mapStyle = findBaseMapStyle(savedId));
    // Style remounts TileLayer via ValueKey — nudge so the new layer paints.
    kickMapTileLayer(_mapController);
  }

  Future<void> _changeMapStyle(BaseMapStyle style) async {
    setState(() => _mapStyle = style);
    kickMapTileLayer(_mapController);
    final box = await Hive.openBox<String>(_metaBoxName);
    await box.put(_mapStyleKey, style.id);
  }

  Future<void> _startLocationUpdates() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) {
          setState(
            () => _locationError = AppLocalizations.of(
              context,
            )!.locationServiceDisabledError,
          );
          _showOfflineGpsHint();
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(
            () => _locationError = AppLocalizations.of(
              context,
            )!.locationPermissionDeniedError,
          );
          _showOfflineGpsHint();
        }
        return;
      }
    } catch (_) {
      // No geolocation support on this platform/browser - the map still
      // works, just without a "you are here" marker.
      if (mounted) {
        setState(
          () => _locationError = AppLocalizations.of(
            context,
          )!.locationPermissionDeniedError,
        );
        _showOfflineGpsHint();
      }
      return;
    }

    _positionSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen((pos) {
          if (!mounted) return;
          if (!isAcceptableLivePosition(pos)) return;
          final location = LatLng(pos.latitude, pos.longitude);
          final firstFix = !_hadGpsFix;
          setState(() {
            _currentLocation = location;
            _locationError = null;
            _hadGpsFix = true;
          });
          // As soon as a fix arrives, switch the under-button status to online.
          if (firstFix) _showOnlineGpsFlash(pos.accuracy);
          if (!_centeredOnce) {
            _centeredOnce = true;
            // A wide, regional view by default - just placing the dot, not
            // zooming in close. The locate-me button still zooms in close
            // (see _recenter) since that's a deliberate "take me there".
            _mapController.move(location, _defaultZoom);
            // move() can be a no-op vs initialCenter/zoom and leave tiles blank.
            kickMapTileLayer(_mapController);
          }
        });
  }

  @override
  void dispose() {
    _dailyModeListened?.removeListener(_onDailyModeChanged);
    _dailyCoordinator?.dispose();
    _gpsFlashTimer?.cancel();
    _positionSub?.cancel();
    super.dispose();
  }

  /// Recenters on the live GPS fix. While a recording is in progress this
  /// opens [RecordScreen] on the map page (with the live track) instead of
  /// only moving the home camera — home and record map stay one place.
  Future<void> _recenter() async {
    final recorder = context.read<GpsRecorder>();
    if (!recorder.isIdle) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const RecordScreen(initialShowMap: true),
        ),
      );
      return;
    }
    final pos = await fetchFreshDevicePosition();
    if (!mounted) return;
    final location = pos != null
        ? LatLng(pos.latitude, pos.longitude)
        : _currentLocation;
    if (location != null) {
      setState(() {
        _currentLocation = location;
        _locationError = null;
        if (pos != null) _hadGpsFix = true;
      });
      _mapController.move(location, 15);
      kickMapTileLayer(_mapController);
    }
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
      builder: (_) =>
          MapStylePickerDialog(current: _mapStyle, onSelected: _changeMapStyle),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final showUpdateBanner = context.watch<AppUpdateController>().showBanner;
    final recordingInProgress = !context.watch<GpsRecorder>().isIdle;
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
                  children: [
                    _RoundIconButton(
                      icon: Icons.list,
                      tooltip: l10n.routesDialogTitle,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const RouteListScreen(),
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Same round glass style as the list button - the plain
                    // AppBar IconButton used to vanish on satellite tiles.
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
                    const RecordingRowIcon(),
                  ],
                ),
              ),
            ),
          ),
          if (_locationError != null || showUpdateBanner)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(64, 8, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showUpdateBanner) ...[
                        const AppUpdateBanner(),
                        const SizedBox(height: 8),
                      ],
                      if (_locationError != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _locationError!,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          // A recording already running (elsewhere, in the background) has
          // its own way back in - the blinking REC pill from
          // RecordingIndicatorOverlay - so this button doesn't double up as
          // a second, confusing "start" invitation while one is live.
          if (!recordingInProgress)
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FloatingActionButton(
                      heroTag: 'homeRecord',
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      tooltip: l10n.recordRideTooltip,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const RecordScreen()),
                      ),
                      child: const Icon(Icons.fiber_manual_record, size: 28),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: SatelliteCountBadge(),
                    ),
                    if (_gpsFlashMessage != null)
                      IgnorePointer(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 260),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                child: Text(
                                  _gpsFlashMessage!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Positioned(
            right: 16,
            bottom: 24,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'homeMapStyle',
                  onPressed: _showMapStylePicker,
                  child: Icon(_mapStyle.icon),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'homeZoomIn',
                  onPressed: _zoomIn,
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'homeZoomOut',
                  onPressed: _zoomOut,
                  child: const Icon(Icons.remove),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'homeLocate',
                  onPressed: _recenter,
                  child: const Icon(Icons.my_location),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final vehicleIcon = context.watch<VehicleIconController>().option;
    final recorder = context.watch<GpsRecorder>();
    final markerSize = vehicleMarkerSize(vehicleIcon);
    final trackPoints = recorder.points;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentLocation ?? kUnknownLocationMapCenter,
        initialZoom: _defaultZoom,
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
        // Same live red track as RecordScreen so leaving the record UI
        // doesn't hide the ride on the "outer" map.
        if (trackPoints.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [for (final p in trackPoints) p.latLng],
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
                width: markerSize,
                height: markerSize,
                child: buildVehicleMarker(vehicleIcon),
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
