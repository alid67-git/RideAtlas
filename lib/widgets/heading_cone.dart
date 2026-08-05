import 'dart:math';

import 'package:flutter/material.dart';

/// A translucent, MotionX-GPS-style "cone of light" fanning out from the
/// vehicle marker in the current GPS heading direction - drawn separately
/// from the marker itself (which stays upright/unrotated) so it can carry
/// direction even in north-up mode, where the map and the marker don't
/// rotate but the rider's actual course still matters.
class HeadingCone extends StatelessWidget {
  const HeadingCone({super.key, required this.size, required this.color});

  /// Diameter of the square area the cone is painted into. The cone's tip
  /// sits at the center and it extends outward toward the edge.
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _HeadingConePainter(color: color)),
    );
  }
}

class _HeadingConePainter extends CustomPainter {
  _HeadingConePainter({required this.color});

  final Color color;

  /// Half-angle of the cone, so the full spread is roughly 60 degrees.
  static const _halfAngle = 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Angle 0 = straight up (screen "north"/"forward"), matching how the
    // vehicle marker itself is drawn pointing up.
    const up = -pi / 2;
    final path = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        up - _halfAngle,
        _halfAngle * 2,
        false,
      )
      ..close();

    final gradient = RadialGradient(
      colors: [color.withValues(alpha: 0.55), color.withValues(alpha: 0.0)],
    );
    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromCircle(center: center, radius: radius),
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HeadingConePainter oldDelegate) =>
      oldDelegate.color != color;
}
