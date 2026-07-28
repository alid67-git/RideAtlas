import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';

import '../build_info.dart';
import '../l10n/gen/app_localizations.dart';
import '../models/gpx_route.dart';
import '../repositories/route_repository.dart';
import '../widgets/route_card.dart';
import 'language_picker.dart';
import 'map_screen.dart';
import 'multi_route_map_screen.dart';

const _metaBoxName = 'rideatlas_meta';
const _lastSeenBuildKey = 'last_seen_build';

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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MultiRouteMapScreen(routeIds: _selectedIds.toList()),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowWhatsNew());
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
      Navigator.of(context).push(
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final repo = context.watch<RouteRepository>();
    final routes = repo.routes;

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
          if (routes.length > 1)
            IconButton(
              icon: Icon(
                _selectionMode ? Icons.close : Icons.checklist,
              ),
              tooltip: _selectionMode
                  ? l10n.exitSelectionTooltip
                  : l10n.selectRoutesTooltip,
              onPressed: _toggleSelectionMode,
            ),
          if (!_selectionMode) const LanguagePickerButton(),
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
                  onTap: () => Navigator.of(context).push(
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
                : FloatingActionButton.extended(
                    onPressed: _showSelectedOnMap,
                    icon: const Icon(Icons.map),
                    label: Text(l10n.showOnMapButton(_selectedIds.length)),
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
