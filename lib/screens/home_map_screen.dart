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
import '../models/gpx_route.dart';
import '../repositories/vehicle_icon_controller.dart';
import '../services/app_update_controller.dart';
import '../services/daily_analysis.dart' show colorForDay;
import '../services/gps_recorder.dart';
import '../services/live_location.dart';
import '../services/map_camera_fit.dart';
import '../services/native_recording.dart';
import '../services/track_display_loader.dart';
import '../widgets/app_update_ui.dart';
import '../widgets/recording_indicator.dart';
import '../widgets/satellite_count_badge.dart';
import '../widgets/vehicle_marker.dart';
import 'map_screen.dart' show MapStylePickerDialog, RouteMapScreen;
import 'record_screen.dart';
import '../services/track_display_simplify.dart';
import '../services/track_io.dart';
import '../repositories/route_repository.dart';
import '../widgets/route_picker_dialog.dart';
import 'settings_screen.dart';

const _metaBoxName = 'rideatlas_meta';
const _mapStyleKey = 'base_map_style_id';
const _lastSeenBuildKey = 'last_seen_build';
const _homeOverlayRouteIdsKey = 'home_overlay_route_ids';

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

  static const _gpsFlashDuration = Duration(seconds: 4);

  /// Saved routes shown as an overlay directly on this map (no separate
  /// screen) - see [_applyOverlayRoutes]. Persisted so they come back
  /// automatically next time this screen is shown, "as if never closed".
  Set<String> _overlayRouteIds = {};
  final List<_HomeOverlayTrack> _overlayTracks = [];
  final _overlayPolylines = ValueNotifier<List<Polyline>>(const []);
  String? _labeledTrackId;
  LatLng? _labeledTrackPoint;
  String? _labeledTrackName;

  @override
  void initState() {
    super.initState();
    _loadOverlayRoutePreference();
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
      if (NativeRecording.isSupported) await _restoreInterruptedRecording();
    });
    _loadMapStyle();
    _startLocationUpdates();
  }

  /// Like Motion GPX: if a recording was in progress when the app was
  /// killed/locked, reopen continues that session and jumps back into
  /// [RecordScreen]. Idle stays idle. Replaces the old "always delete
  /// orphaned points on launch" behaviour, which threw away recoverable
  /// rides.
  Future<void> _restoreInterruptedRecording() async {
    try {
      final recorder = context.read<GpsRecorder>();
      final l10n = AppLocalizations.of(context)!;
      final restored = await recorder.tryRestoreInterruptedSession(
        androidNotificationTitle: l10n.recordingNotificationTitle,
        androidNotificationText: l10n.recordingNotificationText,
      );
      if (!restored || !mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RecordScreen(
            showResumedBanner: true,
            initialCenter: _currentLocation,
            // Restore last Data/Map page rather than always forcing map.
          ),
        ),
      );
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
    _gpsFlashTimer?.cancel();
    _positionSub?.cancel();
    _overlayPolylines.dispose();
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
          builder: (_) => RecordScreen(
            initialShowMap: true,
            useSavedPagePreference: false,
            initialCenter: _currentLocation,
          ),
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
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (mounted) kickMapTileLayer(_mapController);
      });
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

  /// Restores whichever routes were last shown as an overlay here - drawn
  /// immediately, without waiting for any user action, so this screen picks
  /// up exactly where it left off. Silently drops ids for routes deleted
  /// since; applies nothing if the saved set is now empty.
  Future<void> _loadOverlayRoutePreference() async {
    final box = await Hive.openBox<String>(_metaBoxName);
    final saved = box.get(_homeOverlayRouteIdsKey);
    if (!mounted || saved == null || saved.isEmpty) return;
    final savedIds = saved.split(',').toSet();
    final availableIds = context
        .read<RouteRepository>()
        .routes
        .map((r) => r.id)
        .toSet();
    final idsToShow = savedIds.intersection(availableIds);
    if (idsToShow.isEmpty) return;
    await _applyOverlayRoutes(idsToShow);
  }

  Future<void> _persistOverlayRouteIds(Set<String> ids) async {
    final box = await Hive.openBox<String>(_metaBoxName);
    await box.put(_homeOverlayRouteIdsKey, ids.join(','));
  }

  /// Draws [ids] directly on this map - no separate screen, so leaving via
  /// the system back button (there's nowhere else to go from Home) can
  /// never lose them the way a pushed screen's state would. An empty set
  /// clears the overlay; both cases are always persisted (unlike the old
  /// "skip saving when empty" bug that left a stale non-empty selection
  /// stuck in memory after deliberately clearing it).
  Future<void> _applyOverlayRoutes(Set<String> ids) async {
    unawaited(_persistOverlayRouteIds(ids));
    if (ids.isEmpty) {
      setState(() {
        _overlayRouteIds = {};
        _overlayTracks.clear();
        _labeledTrackId = null;
        _labeledTrackPoint = null;
        _labeledTrackName = null;
      });
      _overlayPolylines.value = const [];
      return;
    }

    setState(() {
      _overlayRouteIds = ids;
      _overlayTracks.clear();
    });
    _overlayPolylines.value = const [];

    final repo = context.read<RouteRepository>();
    final byId = {for (final r in repo.routes) r.id: r};
    final selectedRoutes = [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
    if (selectedRoutes.isEmpty) return;

    final budget = mapDisplayBudget(selectedRoutes.length);
    final loaded = await loadTracksForMapDisplay(
      repo: repo,
      routes: selectedRoutes,
      maxPoints: budget.maxPoints,
      minSpacingMeters: budget.minSpacingMeters,
      isCancelled: () => !mounted,
    );
    if (!mounted) return;

    final built = <Polyline>[];
    _overlayTracks.clear();
    for (final track in loaded) {
      final color = colorForDay(track.index);
      _overlayTracks.add(
        _HomeOverlayTrack(
          id: track.route.id,
          name: track.route.name,
          points: track.points,
          color: color,
        ),
      );
      built.add(Polyline(points: track.points, strokeWidth: 4, color: color));
    }
    _overlayPolylines.value = built;
    _fitOverlayTracks(selectedRoutes);
  }

  /// MediaAtlas-style: frame the overlay (1 route → that track, N → union),
  /// including the device location dot so it doesn't get framed out.
  void _fitOverlayTracks(List<GpxRoute> routes) {
    var bounds = boundsForRoutes(routes);
    if (_currentLocation != null) {
      bounds = extendBoundsWithPoints(bounds, [_currentLocation!]);
    }
    if (bounds == null) return;
    fitMapToBounds(
      _mapController,
      bounds: bounds,
      padding: const EdgeInsets.fromLTRB(48, 140, 48, 170),
    );
  }

  void _toggleTrackLabel({
    required String id,
    required String name,
    required LatLng point,
  }) {
    setState(() {
      if (_labeledTrackId == id) {
        _labeledTrackId = null;
        _labeledTrackName = null;
        _labeledTrackPoint = null;
      } else {
        _labeledTrackId = id;
        _labeledTrackName = name;
        _labeledTrackPoint = point;
      }
    });
  }

  /// Rough geographic hit-test: nearest polyline within ~35 m * 2^(15-zoom).
  void _onMapTap(TapPosition tapPosition, LatLng latlng) {
    final hit = findNearestTrackHit(
      tap: latlng,
      zoom: _mapController.camera.zoom,
      tracks: [
        for (final track in _overlayTracks)
          (id: track.id, name: track.name, points: track.points),
      ],
    );
    if (hit == null) {
      if (_labeledTrackId != null) {
        setState(() {
          _labeledTrackId = null;
          _labeledTrackName = null;
          _labeledTrackPoint = null;
        });
      }
      return;
    }
    _toggleTrackLabel(id: hit.id, name: hit.name, point: hit.point);
  }

  void _openRouteDetail(String routeId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RouteMapScreen(routeId: routeId)),
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
                    PopupMenuButton<_HomeTrackMenuAction>(
                      tooltip: l10n.recordOverlayTooltip,
                      position: PopupMenuPosition.under,
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: _HomeTrackMenuAction.pick,
                          child: Text(l10n.recordOverlaySelectMenuItem),
                        ),
                        PopupMenuItem(
                          value: _HomeTrackMenuAction.importFile,
                          child: Text(l10n.recordOverlayImportMenuItem),
                        ),
                      ],
                      onSelected: _onHomeTrackMenuAction,
                      child: Material(
                        color: Theme.of(context)
                            .colorScheme
                            .surface
                            .withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(20),
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Text(
                            l10n.routesDialogTitle,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
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
                        MaterialPageRoute(
                          builder: (_) => RecordScreen(
                            initialCenter: _currentLocation,
                          ),
                        ),
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
    final l10n = AppLocalizations.of(context)!;
    final vehicleIcon = context.watch<VehicleIconController>().option;
    final recorder = context.watch<GpsRecorder>();
    final markerSize = vehicleMarkerSize(vehicleIcon);
    final trackPoints = recorder.points;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentLocation ?? kUnknownLocationMapCenter,
        initialZoom: _defaultZoom,
        onTap: _onMapTap,
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
        ValueListenableBuilder<List<Polyline>>(
          valueListenable: _overlayPolylines,
          builder: (context, overlayLines, _) {
            if (overlayLines.isEmpty && trackPoints.length <= 1) {
              return const SizedBox.shrink();
            }
            return PolylineLayer(
              polylines: [
                ...overlayLines,
                // Same live red track as RecordScreen so leaving the record
                // UI doesn't hide the ride on the "outer" map.
                if (trackPoints.length > 1)
                  Polyline(
                    points: [for (final p in trackPoints) p.latLng],
                    strokeWidth: 4,
                    color: const Color(0xFFE53935),
                  ),
              ],
            );
          },
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
        if (_labeledTrackPoint != null && _labeledTrackName != null)
          MarkerLayer(
            markers: [
              Marker(
                point: _labeledTrackPoint!,
                width: 220,
                height: 76,
                alignment: Alignment.bottomCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Text(
                          _labeledTrackName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => _openRouteDetail(_labeledTrackId!),
                      child: Text(
                        l10n.routeDetailedAnalysisButton,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
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

  Future<List<String>?> _confirmShowAllRouteIds(List<String> allIds) async {
    final l10n = AppLocalizations.of(context)!;
    if (allIds.length > kShowAllRoutesHardCap) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.showAllTracksTooManyTitle),
          content: Text(
            l10n.showAllTracksTooManyMessage(
              allIds.length,
              kShowAllRoutesHardCap,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.showAllTracksLimitButton),
            ),
          ],
        ),
      );
      if (ok != true) return null;
      return allIds.take(kShowAllRoutesHardCap).toList();
    }
    if (allIds.length > kShowAllRoutesSoftCap) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.showAllTracksHeavyTitle),
          content: Text(l10n.showAllTracksHeavyMessage(allIds.length)),
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
        ),
      );
      if (ok != true) return null;
    }
    return allIds;
  }

  Future<void> _onHomeTrackMenuAction(_HomeTrackMenuAction action) async {
    switch (action) {
      case _HomeTrackMenuAction.pick:
        final ids = await _pickRoutesForOverlay();
        if (ids == null || !mounted) return;
        // Exactly one route: that's a request to inspect *that* ride in
        // detail (day analysis, elevation, weather, full resolution), not
        // to set what's overlaid on Home - leaves the existing overlay,
        // if any, untouched.
        if (ids.length == 1) {
          _openRouteDetail(ids.first);
          return;
        }
        await _applyOverlayRoutes(ids.toSet());
      case _HomeTrackMenuAction.importFile:
        await _importTracksFromHome();
    }
  }

  /// The routes checked here start out as whatever is currently overlaid
  /// on Home - so reopening "Rota seç..." and tapping Göster without
  /// changing anything just continues the current view instead of starting
  /// from a blank picker every time.
  Future<List<String>?> _pickRoutesForOverlay() async {
    final l10n = AppLocalizations.of(context)!;
    final routes = context.read<RouteRepository>().routes;
    if (routes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.recordOverlayNoRoutes)),
      );
      return null;
    }
    final selected = await showRoutePickerDialog(
      context: context,
      routes: routes,
      initiallySelected: _overlayRouteIds,
    );
    if (selected == null || selected.isEmpty) return selected?.toList();
    return _confirmShowAllRouteIds(selected.toList());
  }

  Future<void> _importTracksFromHome() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await pickTrackFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty || !mounted) return;

    final repo = context.read<RouteRepository>();
    final importedIds = <String>[];
    var skipped = 0;
    String? lastError;

    for (final file in result.files) {
      if (!isSupportedTrackFileName(file.name)) {
        skipped++;
        lastError = l10n.unsupportedTrackFileType;
        continue;
      }
      final bytes = file.bytes;
      if (bytes == null) {
        skipped++;
        lastError = l10n.fileNotReadable;
        continue;
      }
      try {
        final route = await repo.importFromBytes(
          bytes: bytes,
          suggestedFileName: file.name,
        );
        importedIds.add(route.id);
      } on DuplicateRouteException catch (e) {
        // Already saved — still open it so the rider sees the track.
        if (!importedIds.contains(e.existing.id)) {
          importedIds.add(e.existing.id);
        }
        lastError = l10n.duplicateRouteMessage(e.existing.name);
      } on FormatException {
        skipped++;
        lastError = l10n.trackHasNoPoints;
      } catch (e) {
        skipped++;
        lastError = l10n.importFailedGeneric('$e');
      }
    }

    if (!mounted) return;

    if (importedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lastError ?? l10n.fileNotReadable)),
      );
      return;
    }

    final parts = <String>[l10n.importedRoutesCount(importedIds.length)];
    if (skipped > 0) {
      parts.add(l10n.importSkippedCount(skipped));
    } else if (lastError != null &&
        result.files.length == 1 &&
        importedIds.length == 1) {
      // Single file that was already saved: say so instead of "1 imported".
      parts
        ..clear()
        ..add(lastError);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(parts.join(' '))),
    );

    // A single imported file goes to its own detail page (day analysis,
    // full resolution); several go straight onto Home's overlay alongside
    // whatever was already shown, same as picking multiple via "Rota seç...".
    if (importedIds.length == 1) {
      _openRouteDetail(importedIds.first);
      return;
    }
    await _applyOverlayRoutes({..._overlayRouteIds, ...importedIds});
  }
}

enum _HomeTrackMenuAction { pick, importFile }

class _HomeOverlayTrack {
  const _HomeOverlayTrack({
    required this.id,
    required this.name,
    required this.points,
    required this.color,
  });

  final String id;
  final String name;
  final List<LatLng> points;
  final Color color;
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
