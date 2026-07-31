import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/base_map_style.dart';
import '../repositories/route_repository.dart';
import '../services/gps_recorder.dart';
import '../services/track_io.dart';
import 'map_screen.dart' show RouteMapScreen;

/// Records a ride live using the browser's Geolocation API (via
/// [GpsRecorder]) and, once finished, saves it through the same import
/// pipeline as a regular GPX file. Foreground-only: see
/// AppLocalizations.recordingForegroundNotice for the reason.
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

  @override
  void initState() {
    super.initState();
    _recorder.addListener(_onRecorderChanged);
    // Refreshes the elapsed-time label even between GPS fixes.
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_recorder.isRecording && mounted) setState(() {});
    });
  }

  void _onRecorderChanged() {
    if (!mounted) return;
    setState(() {});
    final points = _recorder.points;
    if (points.isNotEmpty) {
      final zoom = _mapController.camera.zoom;
      _mapController.move(points.last.latLng, zoom < 15 ? 16 : zoom);
    }
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _recorder.removeListener(_onRecorderChanged);
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    final error = await _recorder.start();
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
    }
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
          l10n.recordingForegroundNotice,
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

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: points.isNotEmpty
            ? points.last.latLng
            : const LatLng(41.0082, 28.9784),
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
        if (points.isNotEmpty)
          MarkerLayer(
            markers: [
              Marker(
                point: points.last.latLng,
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
