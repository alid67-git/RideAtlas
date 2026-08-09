import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../l10n/gen/app_localizations.dart';
import '../services/gallery_scan.dart';

/// Shown right after a recording is saved, if [findGalleryMediaBetween]
/// turned up any gallery photos/videos taken during the ride. A grid of
/// checkable thumbnails - everything starts selected, since these are shots
/// the rider took themselves during this exact ride, most of which they'll
/// want attached; unchecking the odd unrelated one is less friction than
/// having to opt in to every single item.
///
/// Pops with the selected subset, or an empty list if the rider taps
/// "Atla"/back without choosing anything.
class RidePhotoPickerScreen extends StatefulWidget {
  const RidePhotoPickerScreen({super.key, required this.candidates});

  final List<GalleryCandidate> candidates;

  @override
  State<RidePhotoPickerScreen> createState() => _RidePhotoPickerScreenState();
}

class _RidePhotoPickerScreenState extends State<RidePhotoPickerScreen> {
  late final Set<int> _selected = {
    for (var i = 0; i < widget.candidates.length; i++) i,
  };

  void _finish(bool addSelected) {
    final result = addSelected
        ? [for (final i in _selected) widget.candidates[i]]
        : const <GalleryCandidate>[];
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _finish(false);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.ridePhotoPickerTitle)),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.ridePhotoPickerMessage(widget.candidates.length),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: widget.candidates.length,
                itemBuilder: (context, i) {
                  final candidate = widget.candidates[i];
                  final selected = _selected.contains(i);
                  return GestureDetector(
                    onTap: () => setState(() {
                      if (selected) {
                        _selected.remove(i);
                      } else {
                        _selected.add(i);
                      }
                    }),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: _GalleryThumb(asset: candidate.asset),
                        ),
                        if (candidate.asset.type == AssetType.video)
                          const Positioned(
                            left: 4,
                            bottom: 4,
                            child: Icon(
                              Icons.videocam,
                              color: Colors.white,
                              shadows: [
                                Shadow(color: Colors.black, blurRadius: 4),
                              ],
                            ),
                          ),
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Icon(
                            selected
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            color: selected ? Colors.white : Colors.white70,
                            shadows: const [
                              Shadow(color: Colors.black, blurRadius: 4),
                            ],
                          ),
                        ),
                        if (selected)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary,
                                width: 3,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _finish(false),
                        child: Text(l10n.ridePhotoPickerSkipButton),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _selected.isEmpty
                            ? null
                            : () => _finish(true),
                        child: Text(
                          l10n.ridePhotoPickerAddButton(_selected.length),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryThumb extends StatelessWidget {
  const _GalleryThumb({required this.asset});

  final AssetEntity asset;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: asset.thumbnailDataWithSize(const ThumbnailSize.square(300)),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return const ColoredBox(color: Colors.black12);
        }
        return Image.memory(bytes, fit: BoxFit.cover);
      },
    );
  }
}
