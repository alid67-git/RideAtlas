import 'package:flutter/material.dart';

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
    // Colorful OpenTopoMap-style outdoor tiles. The original
    // tile.opentopomap.org host rate-limits under pan/zoom load; combined
    // with a full-layer tile reset that caused visible flicker ("kare kare
    // yanıp sönme"). openmaps.fr runs a maintained OTM-compatible renderer
    // built for embedding at modest free-app volume (CC-BY-SA).
    urlTemplate: 'https://tile.openmaps.fr/opentopomap/{z}/{x}/{y}.png',
    attribution:
        'OpenStreetMap katkıda bulunanlar, SRTM | OpenTopoMap (CC-BY-SA), openmaps.fr',
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
