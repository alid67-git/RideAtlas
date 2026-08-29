import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/base_map_style.dart';
import '../models/gpx_route.dart';

/// MediaAtlas-style camera framing: one route fills the window; several
/// routes zoom out to the union of all their bounds.
LatLngBounds? boundsForRoutes(Iterable<GpxRoute> routes) {
  LatLngBounds? bounds;
  for (final route in routes) {
    final next = LatLngBounds(
      LatLng(route.south, route.west),
      LatLng(route.north, route.east),
    );
    if (bounds == null) {
      bounds = next;
    } else {
      bounds.extendBounds(next);
    }
  }
  return bounds;
}

/// Extends [bounds] (or starts a new one) with GPS points. Returns null when
/// there is nothing to frame.
LatLngBounds? extendBoundsWithPoints(
  LatLngBounds? bounds,
  Iterable<LatLng> points,
) {
  final list = points is List<LatLng> ? points : points.toList();
  if (list.length < 2) return bounds;
  final next = LatLngBounds.fromPoints(list);
  if (bounds == null) return next;
  bounds.extendBounds(next);
  return bounds;
}

/// Fits [mapController] to [bounds] with padding, then nudges tiles so the
/// first frame after a programmatic move still fetches imagery.
void fitMapToBounds(
  MapController mapController, {
  required LatLngBounds bounds,
  EdgeInsets padding = const EdgeInsets.all(48),
}) {
  mapController.fitCamera(
    CameraFit.bounds(bounds: bounds, padding: padding),
  );
  kickMapTileLayer(mapController);
}
