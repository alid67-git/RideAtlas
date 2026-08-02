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
import '../repositories/route_repository.dart';
import '../services/gps_recorder.dart';
import '../services/track_io.dart';
import 'map_screen.dart' show RouteMapScreen;

/// True on a native Android build, where [GpsRecorder] runs a foreground
/// service and recording survives the app being minimized. Everywhere else
/// (web, other platforms) recording only continues while this screen is the
/// active, visible tab/app.
final _supportsBackgroundRecording =
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Records a ride live using [GpsRecorder] and, once finished, saves it
/// through the same import pipeline as a regular GPX file. On Android this
/// keeps recording while the app is minimized (a foreground service); on
/// other platforms it only runs while this screen stays in the foreground -
/// see AppLocalizations.recordingForegroundNotice for that case.
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  final _recorder = GpsRecorder();
  final _mapController = MapController();
  Timer? _tickTimer;
  bool _starting = false;
  bool _saving = false;

  /// The device's live position, tracked independently of [_recorder] so the
  /// map shows "you are here" immediately on opening this screen - before
  /// recording starts, and during the brief gap before the recorder's own
  /// stream produces its first point. Stopped once recording actually
  /// begins, since [_recorder.points] takes over as the map's source of
  /// truth from there (no need for two simultaneous GPS subscriptions).
  StreamSubscription<Position>? _liveLocationSub;
  LatLng? _currentLocation;
  bool _centeredOnce = false;

  /// True while the map should keep auto-centering on the live position.
  /// Any user-driven map interaction (drag, pinch, fling, ...) turns this
  /// off, so panning around to look at the surroundings isn't constantly
  /// fought by the auto-follow; the recenter button turns it back on.
  bool _followMe = true;
  late final StreamSubscription<MapEvent> _mapEventSub;

  @override
  void initState() {
    super.initState();
    _recorder.addListener(_onRecorderChanged);
    _startLiveLocation();
    _mapEventSub = _mapController.mapEventStream.listen((event) {
      if (event.source != MapEventSource.mapController && _followMe) {
        setState(() => _followMe = false);
      }
    });
    // Refreshes the elapsed-time label even between GPS fixes.
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_recorder.isRecording && mounted) setState(() {});
    });
  }

  LatLng? get _latestKnownLocation =>
      _recorder.points.isNotEmpty ? _recorder.points.last.latLng : _currentLocation;

  void _recenter() {
    final location = _latestKnownLocation;
    setState(() => _followMe = true);
    if (location != null) {
      final zoom = _mapController.camera.zoom;
      _mapController.move(location, zoom < 15 ? 16 : zoom);
    }
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

    _liveLocationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      if (!mounted) return;
      final location = LatLng(pos.latitude, pos.longitude);
      setState(() => _currentLocation = location);
      if (!_centeredOnce) {
        _centeredOnce = true;
        _mapController.move(location, 16);
      } else if (_followMe) {
        _mapController.move(location, _mapController.camera.zoom);
      }
    });
  }

  void _onRecorderChanged() {
    if (!mounted) return;
    setState(() {});
    final points = _recorder.points;
    if (points.isNotEmpty && _followMe) {
      final zoom = _mapController.camera.zoom;
      _mapController.move(points.last.latLng, zoom < 15 ? 16 : zoom);
    }
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _liveLocationSub?.cancel();
    _mapEventSub.cancel();
    _recorder.removeListener(_onRecorderChanged);
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
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
      final message = error == RecordingStartError.serviceDisabled
          ? l10n.locationServiceDisabledError
          : l10n.locationPermissionDeniedError;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    // The recorder's own GPS stream is now the map's source of truth - no
    // need for a second, independent subscription.
    _liveLocationSub?.cancel();
    _liveLocationSub = null;
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
      _recorder.discard();
      Navigator.pop(context);
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
    final points = _recorder.stop();
    final gpx = exportTrack(
      name: name,
      points: points,
      waypoints: const [],
      format: TrackFormat.gpx,
    );
    final bytes = Uint8List.fromList(utf8.encode(gpx));
    final repo = context.read<RouteRepository>();
    final route = await repo.importFromBytes(
      bytes: bytes,
      suggestedFileName: '$name.gpx',
    );
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => RouteMapScreen(routeId: route.id)));
  }

  Future<bool> _confirmExit() async {
    if (_recorder.isIdle) return true;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.exitRecordingConfirmTitle),
        content: Text(l10n.exitRecordingConfirmMessage),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return PopScope(
      canPop: _recorder.isIdle,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final confirmed = await _confirmExit();
        if (!confirmed || !context.mounted) return;
        _recorder.discard();
        Navigator.pop(context);
      },
      child: Scaffold(
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
                        icon: Icons.arrow_back,
                        onPressed: () async {
                          final confirmed = await _confirmExit();
                          if (!confirmed || !context.mounted) return;
                          _recorder.discard();
                          Navigator.pop(context);
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: _buildStats(context, l10n)),
                    ],
                  ),
                ),
              ),
            ),
            if (!_followMe)
              Positioned(
                right: 16,
                bottom: 100,
                child: SafeArea(
                  top: false,
                  child: FloatingActionButton.small(
                    heroTag: 'recordRecenter',
                    tooltip: l10n.recenterTooltip,
                    onPressed: _recenter,
                    child: const Icon(Icons.my_location),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: SafeArea(
                top: false,
                child: Center(child: _buildControls(l10n)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    if (_recorder.isIdle) {
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

    final d = _recorder.elapsed;
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    final durationStr = h > 0
        ? '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    final altitude = _recorder.currentAltitude;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                value: '${_recorder.distanceKm.toStringAsFixed(2)} km',
              ),
              _StatColumn(
                label: l10n.speedLabel,
                value:
                    '${_recorder.currentSpeedKmh.toStringAsFixed(0)} km/s',
              ),
              _StatColumn(
                label: l10n.currentAltitudeLabel,
                value: altitude == null ? '—' : '${altitude.round()} m',
              ),
            ],
          ),
        ),
        if (_recorder.isAutoPaused) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              l10n.autoPausedLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildControls(AppLocalizations l10n) {
    if (_recorder.isIdle) {
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
          onPressed: _recorder.isPaused ? _recorder.resume : _recorder.pause,
          child: Icon(_recorder.isPaused ? Icons.play_arrow : Icons.pause),
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
    final points = _recorder.points;
    final style = kBaseMapStyles.first;
    // While recording, the track's own last point is the source of truth;
    // otherwise (idle, or the brief gap before the first point lands) fall
    // back to the independently-tracked live position.
    final markerPoint = points.isNotEmpty
        ? points.last.latLng
        : _currentLocation;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter:
            markerPoint ??
            _currentLocation ??
            const LatLng(41.0082, 28.9784),
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
        if (markerPoint != null)
          MarkerLayer(
            markers: [
              Marker(
                point: markerPoint,
                width: 20,
                height: 20,
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
        Text(value, style: theme.textTheme.titleMedium),
        Text(label, style: theme.textTheme.bodySmall),
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
