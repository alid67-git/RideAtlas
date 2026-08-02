import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../build_info.dart';
import '../l10n/gen/app_localizations.dart';
import '../models/base_map_style.dart';
import '../services/update_checker.dart';
import 'language_picker.dart';
import 'map_screen.dart' show MapStylePickerDialog;
import 'record_screen.dart';
import 'route_list_screen.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowWhatsNew());
    _loadMapStyle();
    _startLocationUpdates();
    if (_supportsUpdateCheck) _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    final info = await checkForAndroidUpdate(kAppBuildLabel);
    if (info != null && mounted) setState(() => _updateInfo = info);
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
            () => _locationError =
                AppLocalizations.of(context)!.locationServiceDisabledError,
          );
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
            () => _locationError =
                AppLocalizations.of(context)!.locationPermissionDeniedError,
          );
        }
        return;
      }
    } catch (_) {
      // No geolocation support on this platform/browser - the map still
      // works, just without a "you are here" marker.
      if (mounted) {
        setState(
          () => _locationError =
              AppLocalizations.of(context)!.locationPermissionDeniedError,
        );
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
          setState(() {
            _currentLocation = location;
            _locationError = null;
          });
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
      builder: (_) => MapStylePickerDialog(
        current: _mapStyle,
        onSelected: _changeMapStyle,
      ),
    );
  }

  Widget? _buildUpdateBanner(AppLocalizations l10n) {
    final info = _updateInfo;
    if (info == null || _updateDismissed) return null;
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
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse(info.downloadUrl),
              mode: LaunchMode.externalApplication,
            ),
            child: Text(l10n.updateButtonLabel),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _updateDismissed = true),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final updateBanner = _buildUpdateBanner(l10n);
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
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const RouteListScreen(),
                        ),
                      ),
                    ),
                    const Spacer(),
                    const LanguagePickerButton(),
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
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Center(
              child: FloatingActionButton.large(
                heroTag: 'homeRecord',
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                tooltip: l10n.recordRideTooltip,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RecordScreen()),
                ),
                child: const Icon(Icons.fiber_manual_record, size: 32),
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
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentLocation ?? const LatLng(41.0082, 28.9784),
        initialZoom: _defaultZoom,
      ),
      children: [
        TileLayer(
          urlTemplate: _mapStyle.urlTemplate,
          subdomains: _mapStyle.subdomains,
          userAgentPackageName: 'com.rideatlas.app',
          maxNativeZoom: 20,
        ),
        if (_currentLocation != null)
          MarkerLayer(
            markers: [
              Marker(
                point: _currentLocation!,
                width: 24,
                height: 24,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blueAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
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
