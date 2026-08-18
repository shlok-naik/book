import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A faint, evenly-spaced dot grid painted behind [child] — the subtle
/// texture used across the onboarding flow's plain background areas so
/// they don't read as flat, empty space.
class DottedBackground extends StatelessWidget {
  const DottedBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return CustomPaint(
      painter: _DotGridPainter(
        color: colors.secondaryText.withValues(alpha: 0.14),
      ),
      child: child,
    );
  }
}

class _DotGridPainter extends CustomPainter {
  _DotGridPainter({required this.color});

  final Color color;

  static const _spacing = 22.0;
  static const _radius = 1.1;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var y = _spacing / 2; y < size.height; y += _spacing) {
      for (var x = _spacing / 2; x < size.width; x += _spacing) {
        canvas.drawCircle(Offset(x, y), _radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter oldDelegate) =>
      oldDelegate.color != color;
}
