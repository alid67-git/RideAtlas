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
import '../repositories/vehicle_icon_controller.dart';
import '../services/app_update_controller.dart';
import '../services/gps_recorder.dart';
import '../services/live_location.dart';
import '../services/native_recording.dart';
import '../widgets/app_update_ui.dart';
import '../widgets/recording_indicator.dart';
import '../widgets/satellite_count_badge.dart';
import '../widgets/vehicle_marker.dart';
import 'map_screen.dart' show MapStylePickerDialog;
import 'record_screen.dart';
import '../services/track_display_simplify.dart';
import 'multi_route_map_screen.dart';
import '../services/track_io.dart';
import '../repositories/route_repository.dart';
import '../widgets/route_picker_dialog.dart';
import 'settings_screen.dart';

const _metaBoxName = 'rideatlas_meta';
const _mapStyleKey = 'base_map_style_id';
const _lastSeenBuildKey = 'last_seen_build';
const _lastShownRouteIdsKey = 'multiroute_last_route_ids';

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
        if (ids == null || ids.isEmpty || !mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MultiRouteMapScreen(routeIds: ids),
          ),
        );
      case _HomeTrackMenuAction.importFile:
        await _importTracksFromHome();
    }
  }

  /// The routes checked here start out as whatever was last shown on
  /// [MultiRouteMapScreen] (same Hive key it persists on close) - so
  /// reopening "Rota seç..." and tapping Göster without changing anything
  /// just continues the previous view instead of starting from a blank
  /// picker every time.
  Future<List<String>?> _pickRoutesForOverlay() async {
    final l10n = AppLocalizations.of(context)!;
    final routes = context.read<RouteRepository>().routes;
    if (routes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.recordOverlayNoRoutes)),
      );
      return null;
    }
    final box = await Hive.openBox<String>(_metaBoxName);
    if (!mounted) return null;
    final availableIds = routes.map((r) => r.id).toSet();
    final lastShown =
        box.get(_lastShownRouteIdsKey)?.split(',').toSet() ?? const {};
    final selected = await showRoutePickerDialog(
      context: context,
      routes: routes,
      initiallySelected: lastShown.intersection(availableIds),
    );
    if (selected == null) return null;
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

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MultiRouteMapScreen(routeIds: importedIds),
      ),
    );
  }
}

enum _HomeTrackMenuAction { pick, importFile }

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
