import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// The step indicator shown across the post-tutorial onboarding flow:
/// tutorial → account → Q1 → Q2 → finish. [currentStep] (1-5) and every
/// step before it are drawn filled, with a filled connecting line
/// leading into them; the rest are hollow. Never shown on the tutorial
/// page itself — only from account onward.
///
/// [bypass] draws a second line as a loop hanging below the main one —
/// down from step `from`, across, up into step `to` — for a path that
/// skipped everything in between, without touching the main line at
/// all. The sign-in shortcut uses this to show account leading straight
/// to finish alongside the ordinary line still running through every
/// dot.
class OnboardingProgressDots extends StatelessWidget {
  const OnboardingProgressDots({
    super.key,
    required this.currentStep,
    this.bypass,
  });

  final int currentStep;
  final ({int from, int to})? bypass;

  static const stepCount = 5;
  static const _labels = ['tutorial', 'account', 'Q1', 'Q2', 'finish'];
  static const _dotSize = 16.0;

  /// How far below the main line the bypass loop hangs — deep enough to
  /// read as a clear loop rather than a second line running alongside
  /// the first.
  static const _bypassOffset = 16.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (var step = 1; step <= stepCount; step++)
              Expanded(
                child: Center(
                  child: Text(
                    _labels[step - 1],
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: step <= currentStep
                          ? colors.primaryText
                          : colors.secondaryText,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        LayoutBuilder(
          builder: (context, constraints) {
            // Each dot sits centered in an equal-width slot — the
            // connector below spans exactly center-to-center across
            // those slots, computed from the actual slot width rather
            // than guessed, so it lines up regardless of how wide the
            // labels are.
            final slotWidth = constraints.maxWidth / stepCount;

            return SizedBox(
              height: _dotSize + _bypassOffset,
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: _dotSize + _bypassOffset,
                    child: CustomPaint(
                      painter: _ConnectorPainter(
                        currentStep: currentStep,
                        bypass: bypass,
                        slotWidth: slotWidth,
                        activeColor: colors.accent,
                        inactiveColor: colors.divider,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: _dotSize,
                    child: Row(
                      children: [
                        for (var step = 1; step <= stepCount; step++)
                          Expanded(
                            child: Center(
                              child: Container(
                                width: _dotSize,
                                height: _dotSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: step <= currentStep
                                      ? colors.accent
                                      : colors.divider,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Draws the ordinary straight line through every dot, then — only when
/// [bypass] is set — a second line looping below it: down from
/// [bypass]'s `from` step, across, up into its `to` step. The main line
/// is never altered by a bypass; the two are independent, sharing only
/// the two points the loop drops from and rises back into.
class _ConnectorPainter extends CustomPainter {
  _ConnectorPainter({
    required this.currentStep,
    required this.bypass,
    required this.slotWidth,
    required this.activeColor,
    required this.inactiveColor,
  });

  final int currentStep;
  final ({int from, int to})? bypass;
  final double slotWidth;
  final Color activeColor;
  final Color inactiveColor;

  static const _strokeWidth = 2.0;
  static const _lineY = (OnboardingProgressDots._dotSize - _strokeWidth) / 2;
  static const _bypassY = _lineY + OnboardingProgressDots._bypassOffset;

  double _centerX(int step) => slotWidth * (step - 1) + slotWidth / 2;

  @override
  void paint(Canvas canvas, Size size) {
    for (var step = 2; step <= OnboardingProgressDots.stepCount; step++) {
      final paint = Paint()
        ..color = step <= currentStep ? activeColor : inactiveColor
        ..strokeWidth = _strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(_centerX(step - 1), _lineY),
        Offset(_centerX(step), _lineY),
        paint,
      );
    }

    final bypass = this.bypass;
    if (bypass != null) {
      final fromX = _centerX(bypass.from);
      final toX = _centerX(bypass.to);
      // Softly rounded corners at each turn, rather than sharp right
      // angles, so the loop reads as one continuous line.
      const radius = 4.0;
      final path = Path()
        ..moveTo(fromX, _lineY)
        ..lineTo(fromX, _bypassY - radius)
        ..quadraticBezierTo(fromX, _bypassY, fromX + radius, _bypassY)
        ..lineTo(toX - radius, _bypassY)
        ..quadraticBezierTo(toX, _bypassY, toX, _bypassY - radius)
        ..lineTo(toX, _lineY);
      canvas.drawPath(
        path,
        Paint()
          ..color = activeColor
          ..strokeWidth = _strokeWidth
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectorPainter oldDelegate) =>
      oldDelegate.currentStep != currentStep ||
      oldDelegate.bypass != bypass ||
      oldDelegate.slotWidth != slotWidth ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.inactiveColor != inactiveColor;
}
