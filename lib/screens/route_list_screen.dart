import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../build_info.dart';
import '../models/gpx_route.dart';
import '../repositories/route_repository.dart';
import '../widgets/route_card.dart';
import 'map_screen.dart';

class RouteListScreen extends StatefulWidget {
  const RouteListScreen({super.key});

  @override
  State<RouteListScreen> createState() => _RouteListScreenState();
}

class _RouteListScreenState extends State<RouteListScreen> {
  bool _importing = false;

  Future<void> _importGpx() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['gpx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    if (!mounted) return;

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      _showError('Dosya okunamadı.');
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
    } on FormatException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('GPX içe aktarılamadı: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _rename(GpxRoute route) async {
    final controller = TextEditingController(text: route.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rotayı yeniden adlandır'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && mounted) {
      await context.read<RouteRepository>().rename(route.id, newName);
    }
  }

  Future<void> _delete(GpxRoute route) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rotayı sil'),
        content: Text('"${route.name}" silinsin mi? Bu işlem geri alınamaz.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
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
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('RideAtlas'),
            Text(
              kAppBuildLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: Consumer<RouteRepository>(
        builder: (context, repo, _) {
          if (repo.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          final routes = repo.routes;
          if (routes.isEmpty) {
            return _EmptyState(onImport: _importing ? null : _importGpx);
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: routes.length,
            itemBuilder: (context, i) {
              final route = routes[i];
              return RouteCard(
                route: route,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => RouteMapScreen(routeId: route.id)),
                ),
                onRename: () => _rename(route),
                onDelete: () => _delete(route),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _importGpx,
        icon: _importing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.add),
        label: const Text('GPX İçe Aktar'),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 72, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              'Henüz rota yok',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Bir .gpx dosyası içe aktararak rotanızı haritada görüntüleyin ve detaylı analiz edin.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add),
              label: const Text('GPX İçe Aktar'),
            ),
          ],
        ),
      ),
    );
  }
}
