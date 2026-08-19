import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// HTTP User-Agent for map tile requests. Must clearly name this app — hosts
/// such as openmaps.fr reject library defaults (okhttp, bare Dart, empty UA)
/// and answer with a "Limited Access" warning PNG instead of map tiles.
const kTileUserAgent = 'RideAtlas (com.rideatlas.app)';

/// Network tile provider that always sends [kTileUserAgent]. Prefer this over
/// relying on flutter_map's `flutter_map (package)` default alone.
///
/// Headers must be a *mutable* map: [TileLayer] calls `headers.putIfAbsent`
/// for User-Agent on non-web platforms. A `const {...}` map throws
/// UnsupportedError there and the release APK stays on a blank white screen.
NetworkTileProvider createRideAtlasTileProvider() => NetworkTileProvider(
      headers: <String, String>{'User-Agent': kTileUserAgent},
    );

/// A selectable base map (tile layer) style. Google's own map tiles can't be
/// hotlinked outside their SDK per their terms of service, so these are
/// free/legally embeddable alternatives covering similar looks (street,
/// clean/political, dark, satellite, topographic).
class BaseMapStyle {
  const BaseMapStyle({
    required this.id,
    required this.label,
    required this.icon,
    required this.urlTemplate,
    required this.attribution,
    this.subdomains = const [],
    this.maxNativeZoom = 20,
  });

  final String id;
  final String label;
  final IconData icon;
  final String urlTemplate;
  final String attribution;
  final List<String> subdomains;

  /// Highest zoom the tile host actually serves. flutter_map upscales beyond
  /// this instead of requesting missing z18+ tiles that 404 and leave gaps.
  final int maxNativeZoom;
}

const kBaseMapStyles = <BaseMapStyle>[
  BaseMapStyle(
    id: 'voyager',
    label: 'Sokak',
    icon: Icons.map,
    urlTemplate:
        'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
    subdomains: ['a', 'b', 'c', 'd'],
    attribution: 'OpenStreetMap katkıda bulunanlar, CARTO',
  ),
  BaseMapStyle(
    id: 'satellite',
    label: 'Uydu',
    icon: Icons.satellite_alt,
    urlTemplate:
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    attribution: 'Esri, Maxar, Earthstar Geographics',
  ),
  BaseMapStyle(
    id: 'topo',
    label: 'Topo',
    icon: Icons.terrain,
    // Colorful OpenTopoMap outdoor tiles (contour + elevation colors).
    // openmaps.fr was tried as a mirror but serves a "Limited Access /
    // User-Agent" warning image when it dislikes the client, which showed
    // up as a big policy dialog on the map. Official OTM (new server since
    // early 2026) plus our non-blast tile retry avoids the old flicker.
    urlTemplate: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
    subdomains: ['a', 'b', 'c'],
    attribution:
        'OpenStreetMap katkıda bulunanlar, SRTM | OpenTopoMap (CC-BY-SA)',
    maxNativeZoom: 17,
  ),
  BaseMapStyle(
    id: 'dark',
    label: 'Koyu',
    icon: Icons.dark_mode,
    urlTemplate:
        'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
    subdomains: ['a', 'b', 'c', 'd'],
    attribution: 'OpenStreetMap katkıda bulunanlar, CARTO',
  ),
  BaseMapStyle(
    id: 'positron',
    label: 'Sade / Siyasi',
    icon: Icons.public,
    urlTemplate:
        'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
    subdomains: ['a', 'b', 'c', 'd'],
    attribution: 'OpenStreetMap katkıda bulunanlar, CARTO',
  ),
];

BaseMapStyle findBaseMapStyle(String? id) {
  return kBaseMapStyles.firstWhere(
    (s) => s.id == id,
    orElse: () => kBaseMapStyles.first,
  );
}
