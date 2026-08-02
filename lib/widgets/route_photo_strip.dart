import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/route_photo.dart';
import '../repositories/photo_repository.dart';

/// A small preview of a route photo, backed by [PhotoRepository]'s in-memory
/// bytes cache (fetching lazily on first build). Used both in the filmstrip
/// and as photo markers on the map.
class PhotoThumb extends StatefulWidget {
  const PhotoThumb({
    super.key,
    required this.photoId,
    this.size = 64,
    this.circle = false,
  });

  final String photoId;
  final double size;
  final bool circle;

  @override
  State<PhotoThumb> createState() => _PhotoThumbState();
}

class _PhotoThumbState extends State<PhotoThumb> {
  @override
  void initState() {
    super.initState();
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant PhotoThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoId != widget.photoId) _ensureLoaded();
  }

  void _ensureLoaded() {
    final repo = context.read<PhotoRepository>();
    if (repo.cachedBytes(widget.photoId) == null) {
      repo.loadBytes(widget.photoId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = context.watch<PhotoRepository>().cachedBytes(
      widget.photoId,
    );
    final content = bytes == null
        ? const ColoredBox(color: Colors.black12)
        : Image.memory(bytes, fit: BoxFit.cover);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: widget.circle
          ? ClipOval(child: content)
          : ClipRRect(borderRadius: BorderRadius.circular(10), child: content),
    );
  }
}

/// Horizontal filmstrip of a route's attached photos, with a leading "add"
/// tile. Tapping a thumbnail opens a full-screen viewer.
class RoutePhotoStrip extends StatelessWidget {
  const RoutePhotoStrip({
    super.key,
    required this.routeId,
    required this.onAddPhoto,
  });

  final String routeId;
  final VoidCallback onAddPhoto;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final photos = context.watch<PhotoRepository>().photosFor(routeId);

    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          Tooltip(
            message: l10n.addPhotoTooltip,
            child: Material(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(10),
              elevation: 2,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onAddPhoto,
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: Icon(
                    Icons.add_a_photo,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
          for (final photo in photos) ...[
            const SizedBox(width: 8),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => showDialog<void>(
                context: context,
                barrierColor: Colors.black,
                builder: (_) => PhotoViewerDialog(
                  routeId: routeId,
                  initialPhotoId: photo.id,
                ),
              ),
              child: PhotoThumb(photoId: photo.id, size: 56),
            ),
          ],
        ],
      ),
    );
  }
}

/// Full-screen swipeable viewer for a route's photos, with a delete action.
class PhotoViewerDialog extends StatefulWidget {
  const PhotoViewerDialog({
    super.key,
    required this.routeId,
    required this.initialPhotoId,
  });

  final String routeId;
  final String initialPhotoId;

  @override
  State<PhotoViewerDialog> createState() => _PhotoViewerDialogState();
}

class _PhotoViewerDialogState extends State<PhotoViewerDialog> {
  late final PageController _controller;
  late int _index;
  List<RoutePhoto> _photos = const [];

  @override
  void initState() {
    super.initState();
    final repo = context.read<PhotoRepository>();
    _photos = repo.photosFor(widget.routeId);
    _index = _photos.indexWhere((p) => p.id == widget.initialPhotoId);
    if (_index < 0) _index = 0;
    _controller = PageController(initialPage: _index);
    for (final photo in _photos) {
      repo.loadBytes(photo.id);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _delete(RoutePhoto photo) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deletePhotoTitle),
        content: Text(l10n.deletePhotoConfirm),
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
    await context.read<PhotoRepository>().delete(photo.id);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final photos = context.watch<PhotoRepository>().photosFor(widget.routeId);
    if (photos.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
      return const SizedBox.shrink();
    }
    final safeIndex = _index.clamp(0, photos.length - 1);
    final photoRepo = context.watch<PhotoRepository>();

    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: photos.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final bytes = photoRepo.cachedBytes(photos[i].id);
              return Center(
                child: bytes == null
                    ? const CircularProgressIndicator(color: Colors.white)
                    : InteractiveViewer(child: Image.memory(bytes)),
              );
            },
          ),
          Positioned(
            top: 8,
            left: 8,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.delete, color: Colors.white),
                onPressed: () => _delete(photos[safeIndex]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
