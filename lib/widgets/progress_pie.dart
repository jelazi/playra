import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Small filled circle showing how far through a video the viewer is.
class ProgressPie extends StatelessWidget {
  const ProgressPie(this.progress, {super.key, this.size = 18});

  final double progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ProgressPiePainter(
          progress: progress.clamp(0, 1).toDouble(),
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          fillColor: theme.colorScheme.primary,
          borderColor: theme.dividerColor,
        ),
      ),
    );
  }
}

class _ProgressPiePainter extends CustomPainter {
  const _ProgressPiePainter({required this.progress, required this.backgroundColor, required this.fillColor, required this.borderColor});

  final double progress;
  final Color backgroundColor;
  final Color fillColor;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.shortestSide / 2;

    canvas.drawCircle(center, radius, Paint()..color = backgroundColor);

    if (progress > 0) {
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, true, Paint()..color = fillColor);
    }

    canvas.drawCircle(
      center,
      radius - 0.5,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _ProgressPiePainter old) =>
      progress != old.progress || backgroundColor != old.backgroundColor || fillColor != old.fillColor || borderColor != old.borderColor;
}
