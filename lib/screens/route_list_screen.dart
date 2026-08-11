import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/gpx_route.dart';
import '../models/track_point.dart';
import '../repositories/photo_repository.dart';
import '../repositories/route_repository.dart';
import '../services/gps_recorder.dart';
import '../services/gpx_parser.dart';
import '../services/track_io.dart';
import '../widgets/recording_indicator.dart';
import '../widgets/route_card.dart';
import 'map_screen.dart';
import 'multi_route_map_screen.dart';
import 'record_screen.dart';
import 'settings_screen.dart';

class RouteListScreen extends StatefulWidget {
  const RouteListScreen({super.key});

  @override
  State<RouteListScreen> createState() => _RouteListScreenState();
}

class _RouteListScreenState extends State<RouteListScreen> {
  bool _importing = false;
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      _selectedIds.clear();
    });
  }

  void _showSelectedOnMap() {
    // Replace, not push: RouteListScreen sits directly on the home map, so
    // this keeps that one-screen depth instead of stacking indefinitely -
    // a single back/pop returns straight to the home map.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MultiRouteMapScreen(routeIds: _selectedIds.toList()),
      ),
    );
  }

  /// Merges the selected routes into one new route, e.g. several separate
  /// day recordings from the same trip. Routes are ordered by their own
  /// first GPS timestamp (falling back to import time for tracks without
  /// timestamps) rather than selection order, so it doesn't matter what
  /// order the rider picked them in. The originals are kept, not deleted -
  /// just renamed with a "(birleştirildi)" suffix - and any photos/videos
  /// attached to them are copied onto the new merged route too.
  Future<void> _mergeSelected() async {
    final l10n = AppLocalizations.of(context)!;
    final repo = context.read<RouteRepository>();
    final photoRepo = context.read<PhotoRepository>();
    final selected = repo.routes
        .where((r) => _selectedIds.contains(r.id))
        .toList();
    if (selected.length < 2) return;

    final loaded = <(GpxRoute route, List<TrackPoint> points, DateTime start)>[];
    for (final route in selected) {
      final xml = await repo.readTrackContent(route);
      final parsed = parseTrackXml(xml);
      final start = trackTimeRange(parsed.points).start ?? route.importedAt;
      loaded.add((route, parsed.points, start));
    }
    loaded.sort((a, b) => a.$3.compareTo(b.$3));
    if (!mounted) return;

    final defaultName = loaded.map((e) => e.$1.name).join(' + ');
    final controller = TextEditingController(text: defaultName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.mergeRouteDialogTitle),
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

    final combinedPoints = [for (final e in loaded) ...e.$2];
    final gpx = exportTrack(
      name: name,
      points: combinedPoints,
      waypoints: const [],
      format: TrackFormat.gpx,
    );
    final merged = await repo.importFromBytes(
      bytes: Uint8List.fromList(utf8.encode(gpx)),
      suggestedFileName: '$name.gpx',
    );
    if (!mounted) return;

    for (final e in loaded) {
      final original = e.$1;
      await repo.rename(original.id, '${original.name} ${l10n.mergedRouteSuffix}');
      if (!mounted) return;
      for (final photo in photoRepo.photosFor(original.id)) {
        final bytes = await photoRepo.loadBytes(photo.id);
        if (bytes == null) continue;
        await photoRepo.add(
          routeId: merged.id,
          bytes: bytes,
          lat: photo.lat,
          lng: photo.lng,
          type: photo.type,
        );
      }
    }
    if (!mounted) return;

    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => RouteMapScreen(routeId: merged.id)),
    );
  }

  Future<void> _importTrack() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['gpx', 'kml', 'kmz'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    if (!mounted) return;

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      _showError(AppLocalizations.of(context)!.fileNotReadable);
      return;
    }

    setState(() => _importing = true);
    try {
      final repo = context.read<RouteRepository>();
      final route = await repo.importFromBytes(
        bytes: bytes,
        suggestedFileName: file.name,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => RouteMapScreen(routeId: route.id)),
      );
    } on FormatException catch (_) {
      if (mounted) _showError(AppLocalizations.of(context)!.trackHasNoPoints);
    } catch (e) {
      if (mounted) {
        _showError(AppLocalizations.of(context)!.importFailedGeneric('$e'));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _rename(GpxRoute route) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: route.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.renameRouteTitle),
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
    if (newName != null && newName.isNotEmpty && mounted) {
      await context.read<RouteRepository>().rename(route.id, newName);
    }
  }

  /// Deletes every currently-selected route (and its attached photos/
  /// videos) after one confirmation for the whole batch, mirroring
  /// [_delete]'s single-route flow.
  Future<void> _deleteSelected() async {
    final l10n = AppLocalizations.of(context)!;
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteRoutesTitle),
        content: Text(l10n.deleteRoutesConfirm(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final repo = context.read<RouteRepository>();
    final photoRepo = context.read<PhotoRepository>();
    for (final id in _selectedIds.toList()) {
      await repo.delete(id);
      if (!mounted) return;
      await photoRepo.deleteForRoute(id);
      if (!mounted) return;
    }
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _delete(GpxRoute route) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteRouteTitle),
        content: Text(l10n.deleteRouteConfirm(route.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<RouteRepository>().delete(route.id);
      if (!mounted) return;
      await context.read<PhotoRepository>().deleteForRoute(route.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final repo = context.watch<RouteRepository>();
    final routes = repo.routes;
    final recordingInProgress = !context.watch<GpsRecorder>().isIdle;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectionMode
              ? l10n.selectedCountTitle(_selectedIds.length)
              : 'RideAtlas',
        ),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: l10n.exitSelectionTooltip,
                onPressed: _toggleSelectionMode,
              )
            : null,
        actions: [
          // "Tümünü göster" - ticking it selects every route at once (the
          // opposite of tapping each card individually), so a rider with
          // many recordings can jump straight to merging/showing all of
          // them on the map without hand-picking each one.
          if (_selectionMode)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => setState(() {
                  if (_selectedIds.length == routes.length) {
                    _selectedIds.clear();
                  } else {
                    _selectedIds
                      ..clear()
                      ..addAll(routes.map((r) => r.id));
                  }
                }),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: routes.isNotEmpty &&
                          _selectedIds.length == routes.length,
                      onChanged: (checked) => setState(() {
                        if (checked ?? false) {
                          _selectedIds
                            ..clear()
                            ..addAll(routes.map((r) => r.id));
                        } else {
                          _selectedIds.clear();
                        }
                      }),
                    ),
                    Text(l10n.showAllRoutesLabel),
                  ],
                ),
              ),
            ),
          if (routes.isNotEmpty)
            IconButton(
              icon: Icon(_selectionMode ? Icons.close : Icons.checklist),
              tooltip: _selectionMode
                  ? l10n.exitSelectionTooltip
                  : l10n.selectRoutesTooltip,
              onPressed: _toggleSelectionMode,
            ),
          if (!_selectionMode && !recordingInProgress)
            IconButton(
              icon: const Icon(Icons.fiber_manual_record, color: Colors.red),
              tooltip: l10n.recordRideTooltip,
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const RecordScreen()),
              ),
            ),
          // Kept visible during selection too - hiding it here left the
          // rider with no way to reach Settings until they exited
          // selection mode first.
          const SettingsButton(),
          if (!_selectionMode) const RecordingRowIcon(),
        ],
      ),
      body: repo.isLoading
          ? const Center(child: CircularProgressIndicator())
          : routes.isEmpty
          ? _EmptyState(onImport: _importing ? null : _importTrack)
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: routes.length,
              itemBuilder: (context, i) {
                final route = routes[i];
                return RouteCard(
                  route: route,
                  selectionMode: _selectionMode,
                  selected: _selectedIds.contains(route.id),
                  onSelectedChanged: (selected) => setState(() {
                    if (selected) {
                      _selectedIds.add(route.id);
                    } else {
                      _selectedIds.remove(route.id);
                    }
                  }),
                  onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => RouteMapScreen(routeId: route.id),
                    ),
                  ),
                  onRename: () => _rename(route),
                  onDelete: () => _delete(route),
                );
              },
            ),
      floatingActionButton: _selectionMode
          ? (_selectedIds.isEmpty
                ? null
                // Horizontally scrollable - Birleştir + Haritada göster +
                // the delete icon together can be wider than the screen on
                // narrow phones once the count digits grow.
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_selectedIds.length > 1) ...[
                          FloatingActionButton.extended(
                            heroTag: 'mergeRoutes',
                            onPressed: _mergeSelected,
                            icon: const Icon(Icons.call_merge),
                            label: Text(
                              l10n.mergeRoutesButton(_selectedIds.length),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        FloatingActionButton.extended(
                          heroTag: 'showOnMap',
                          onPressed: _showSelectedOnMap,
                          icon: const Icon(Icons.map),
                          label: Text(
                            l10n.showOnMapButton(_selectedIds.length),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FloatingActionButton(
                          heroTag: 'deleteSelected',
                          onPressed: _deleteSelected,
                          backgroundColor:
                              Theme.of(context).colorScheme.errorContainer,
                          foregroundColor:
                              Theme.of(context).colorScheme.onErrorContainer,
                          tooltip: l10n.deleteSelectedRoutesTooltip,
                          child: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ))
          : FloatingActionButton.extended(
              onPressed: _importing ? null : _importTrack,
              icon: _importing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add),
              label: Text(l10n.importTrackButton),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onImport});

  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.map_outlined,
              size: 72,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.emptyRoutesTitle,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.emptyRoutesMessage,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add),
              label: Text(l10n.importTrackButton),
            ),
          ],
        ),
      ),
    );
  }
}
