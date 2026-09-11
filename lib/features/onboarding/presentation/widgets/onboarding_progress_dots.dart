import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// The step indicator shown across the post-tutorial onboarding flow:
/// tutorial → look → finish. [currentStep] (1-3) and every step before
/// it are drawn filled, with a filled connecting line leading into them;
/// the rest are hollow. Never shown on the tutorial pages themselves —
/// only from the "pick a look" question onward.
///
/// Three steps rather than the five this once had. Onboarding no longer
/// creates an account — `main` opens an anonymous session before the
/// first frame — so the two account steps, and the branching line that
/// used to loop around them for readers who signed in instead of
/// signing up, have nothing left to draw.
class OnboardingProgressDots extends StatelessWidget {
  const OnboardingProgressDots({super.key, required this.currentStep});

  final int currentStep;

  static const stepCount = 3;
  static const _labels = ['tutorial', 'look', 'finish'];
  static const _dotSize = 16.0;

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
              height: _dotSize,
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: _dotSize,
                    child: CustomPaint(
                      painter: _ConnectorPainter(
                        currentStep: currentStep,
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

/// The straight line running through every dot, filled as far as
/// [currentStep] has reached.
class _ConnectorPainter extends CustomPainter {
  _ConnectorPainter({
    required this.currentStep,
    required this.slotWidth,
    required this.activeColor,
    required this.inactiveColor,
  });

  final int currentStep;
  final double slotWidth;
  final Color activeColor;
  final Color inactiveColor;

  static const _strokeWidth = 2.0;
  static const _lineY = (OnboardingProgressDots._dotSize - _strokeWidth) / 2;

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
  }

  @override
  bool shouldRepaint(_ConnectorPainter old) =>
      old.currentStep != currentStep ||
      old.slotWidth != slotWidth ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor;
}
