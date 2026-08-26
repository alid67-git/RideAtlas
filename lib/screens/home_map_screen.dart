import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../build_info.dart';
import '../l10n/gen/app_localizations.dart';
import '../models/base_map_style.dart';
import '../repositories/vehicle_icon_controller.dart';
import '../services/gps_recorder.dart';
import '../services/native_recording.dart';
import '../services/update_checker.dart';
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

/// Update checks are Android-only: the web build redeploys itself on every
/// visit (no APK to fall behind), and there's no iOS/desktop release yet.
final _supportsUpdateCheck =
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

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
  UpdateInfo? _updateInfo;
  bool _updateDismissed = false;
  bool _installingUpdate = false;

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
      await _maybeShowWhatsNew();
      // After what's-new: offer update with a single "Güncelle" button; the
      // rest (download + install) is automatic with a progress dialog.
      if (_supportsUpdateCheck) await _checkForUpdateAndOffer();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.recordingSessionResumed)),
      );
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const RecordScreen()),
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

  /// Finds a newer android-latest build and offers a one-button dialog
  /// ("Güncelle"). Declining (back / outside tap) keeps the home banner so
  /// the rider can still update later with the same single button.
  Future<void> _checkForUpdateAndOffer() async {
    final info = await checkForAndroidUpdate(kAppBuildLabel);
    if (info == null || !mounted) return;
    setState(() => _updateInfo = info);

    final l10n = AppLocalizations.of(context)!;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.updateAvailableTitle),
        content: Text(l10n.updateAvailableMessage(info.version)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.updateButtonLabel),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (accepted == true) await _installUpdate(info);
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
  }

  Future<void> _changeMapStyle(BaseMapStyle style) async {
    setState(() => _mapStyle = style);
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
          }
        });
  }

  @override
  void dispose() {
    _gpsFlashTimer?.cancel();
    _positionSub?.cancel();
    super.dispose();
  }

  void _recenter() {
    final location = _currentLocation;
    if (location != null) _mapController.move(location, 15);
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

  /// One tap: stream the APK with a MedyaAtlas-style progress dialog, then
  /// hand off to the system installer. No further confirmation steps.
  Future<void> _installUpdate(UpdateInfo info) async {
    if (!mounted || _installingUpdate) return;
    setState(() => _installingUpdate = true);

    final l10n = AppLocalizations.of(context)!;
    final progress = ValueNotifier<(int received, int? total)>((0, null));

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(l10n.updateDownloadingTitle),
          content: ValueListenableBuilder<(int, int?)>(
            valueListenable: progress,
            builder: (context, value, _) {
              final received = value.$1;
              final total = value.$2;
              final fraction = (total != null && total > 0)
                  ? (received / total).clamp(0.0, 1.0)
                  : null;
              final percent = fraction == null
                  ? '…'
                  : '%${(fraction * 100).round()}';
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(value: fraction),
                  const SizedBox(height: 12),
                  Text(
                    l10n.updateDownloadProgress(percent),
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    try {
      await downloadAndInstallUpdate(
        info,
        onProgress: (received, total) {
          progress.value = (received, total);
        },
      );
      if (mounted) setState(() => _updateDismissed = true);
    } catch (_) {
      // In-app install failed (unknown-apps permission, no handler, …) -
      // fall back to a plain browser download.
      if (mounted) {
        await launchUrl(
          Uri.parse(info.downloadUrl),
          mode: LaunchMode.externalApplication,
        );
      }
    } finally {
      progress.dispose();
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        setState(() => _installingUpdate = false);
      }
    }
  }

  Widget? _buildUpdateBanner(AppLocalizations l10n) {
    final info = _updateInfo;
    if (info == null || _updateDismissed || _installingUpdate) return null;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.updateAvailableMessage(info.version),
              style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
            ),
          ),
          // Single action - download + install run automatically after this.
          FilledButton(
            onPressed: () => _installUpdate(info),
            child: Text(l10n.updateButtonLabel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final updateBanner = _buildUpdateBanner(l10n);
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
          if (_locationError != null || updateBanner != null)
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
                      if (updateBanner != null) ...[
                        updateBanner,
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
                  onPressed: _currentLocation == null ? null : _recenter,
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
    final markerSize = vehicleMarkerSize(vehicleIcon);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentLocation ?? const LatLng(41.0082, 28.9784),
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
