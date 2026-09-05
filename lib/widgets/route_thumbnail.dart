import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/gpx_route.dart';

/// A small map-less preview of [route]'s recorded shape, drawn from its
/// cached [GpxRoute.previewPoints] - no GPX re-parsing, so this is as cheap
/// to build as the route list itself. Falls back to a generic route icon for
/// older saved routes that predate the cached preview.
class RouteThumbnail extends StatelessWidget {
  const RouteThumbnail({super.key, required this.route, this.size = 48});

  final GpxRoute route;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = route.previewPoints;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      padding: const EdgeInsets.all(6),
      child: (points == null || points.length < 2)
          ? Icon(Icons.route, color: theme.colorScheme.onPrimaryContainer)
          : CustomPaint(
              painter: _RouteShapePainter(
                points: points,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
    );
  }
}

class _RouteShapePainter extends CustomPainter {
  const _RouteShapePainter({required this.points, required this.color});

  final List<List<double>> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    var minLat = points.first[0], maxLat = points.first[0];
    var minLng = points.first[1], maxLng = points.first[1];
    for (final p in points) {
      if (p[0] < minLat) minLat = p[0];
      if (p[0] > maxLat) maxLat = p[0];
      if (p[1] < minLng) minLng = p[1];
      if (p[1] > maxLng) maxLng = p[1];
    }
    final latSpan = (maxLat - minLat).abs();
    final lngSpan = (maxLng - minLng).abs();
    // Degenerate (near-point) tracks: draw a centered dot rather than
    // dividing by a ~zero span.
    if (latSpan < 1e-9 && lngSpan < 1e-9) {
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        1.5,
        Paint()..color = color,
      );
      return;
    }

    // Longitude degrees are narrower than latitude ones away from the
    // equator - correct so the shape isn't stretched.
    final midLatRad = ((minLat + maxLat) / 2) * (math.pi / 180);
    final lngScale = latSpan == 0
        ? 1.0
        : math.cos(midLatRad).abs().clamp(0.15, 1.0);
    final effectiveLngSpan = lngSpan * lngScale;
    final span = latSpan > effectiveLngSpan ? latSpan : effectiveLngSpan;
    final scale = span == 0 ? 1.0 : size.shortestSide / span;

    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;
    Offset project(List<double> p) {
      final x = size.width / 2 + (p[1] - centerLng) * lngScale * scale;
      // Screen y grows downward; latitude grows northward - flip.
      final y = size.height / 2 - (p[0] - centerLat) * scale;
      return Offset(x, y);
    }

    final start = project(points.first);
    final path = Path()..moveTo(start.dx, start.dy);
    for (final p in points.skip(1)) {
      final o = project(p);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RouteShapePainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}
