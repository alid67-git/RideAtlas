import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/base_map_style.dart';

/// Lets the user manually pick a point on the map - used when a photo or
/// video has no usable location of its own (no EXIF GPS, or a video, which
/// isn't read automatically at all). A pin stays fixed at the screen's
/// center; the user pans the map underneath it, then confirms.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, required this.initialCenter});

  final LatLng initialCenter;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _mapController = MapController();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final style = kBaseMapStyles.first;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.initialCenter,
              initialZoom: 14,
            ),
            children: [
              TileLayer(
                urlTemplate: style.urlTemplate,
                subdomains: style.subdomains,
                userAgentPackageName: 'com.rideatlas.app',
                maxNativeZoom: style.maxNativeZoom,
                evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
              ),
              RichAttributionWidget(
                attributions: [TextSourceAttribution(style.attribution)],
              ),
            ],
          ),
          const IgnorePointer(
            child: Center(
              child: Padding(
                // Offsets the pin so its tip (not its center) points at the
                // screen's true center point.
                padding: EdgeInsets.only(bottom: 36),
                child: Icon(Icons.location_on, size: 48, color: Colors.red),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Material(
                      color: Theme.of(
                        context,
                      ).colorScheme.surface.withValues(alpha: 0.92),
                      shape: const CircleBorder(),
                      elevation: 2,
                      child: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surface.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          l10n.pickLocationInstruction,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pop(context, _mapController.camera.center),
        icon: const Icon(Icons.check),
        label: Text(l10n.confirmLocationButton),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
