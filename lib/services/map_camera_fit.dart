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

/// Constrained world-wrap bound: -85.0511..85.0511 latitude (Web Mercator
/// ceiling), -180..180 longitude - a last-resort fit target below.
final _worldBounds = LatLngBounds(
  const LatLng(-85.0511, -180),
  const LatLng(85.0511, 180),
);

/// Fits [mapController] to [bounds] with padding, then nudges tiles so the
/// first frame after a programmatic move still fetches imagery.
///
/// MedyaAtlas-style: resets rotation to north first - fitting bounds while
/// the map is rotated computes the frame for the wrong orientation, so the
/// route can end up only partly on screen - then verifies the *actual*
/// resulting camera instead of trusting fitCamera to have applied it (a
/// fit can be silently rejected, e.g. before the map has been laid out
/// once), falling back to a whole-world view rather than leaving the
/// button looking like it did nothing.
void fitMapToBounds(
  MapController mapController, {
  required LatLngBounds bounds,
  EdgeInsets padding = const EdgeInsets.all(48),
}) {
  try {
    mapController.rotate(0);
  } catch (_) {
    // Controller not attached yet - the fit below is a no-op too; that's
    // fine, whatever screen calls this will fit again once it is.
  }
  final camera = mapController.camera;
  final fitted = CameraFit.bounds(bounds: bounds, padding: padding).fit(camera);
  if (fitted.zoom.isFinite && fitted.center.latitude.isFinite) {
    mapController.move(fitted.center, fitted.zoom);
    if (_cameraNear(mapController.camera, fitted)) {
      kickMapTileLayer(mapController);
      return;
    }
  }
  final worldFit = CameraFit.bounds(
    bounds: _worldBounds,
    padding: EdgeInsets.zero,
  ).fit(camera);
  if (worldFit.zoom.isFinite) {
    mapController.move(worldFit.center, worldFit.zoom);
  }
  kickMapTileLayer(mapController);
}

bool _cameraNear(MapCamera actual, MapCamera target) {
  return (actual.zoom - target.zoom).abs() < 0.05 &&
      (actual.center.latitude - target.center.latitude).abs() < 0.5 &&
      (actual.center.longitude - target.center.longitude).abs() < 0.5;
}
