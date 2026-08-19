import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// The step indicator shown across the post-tutorial onboarding flow:
/// tutorial → Q1 → account → Q2 → finish. [currentStep] (1-5) and every
/// step before it are drawn filled, with a filled connecting line
/// leading into them; the rest are hollow. Never shown on the tutorial
/// pages themselves — only from Q1 onward.
///
/// [bypass] draws a second line as a loop hanging below the main one —
/// down from step `from`, across, up into step `to` — for a path that
/// skipped everything in between. Steps strictly inside that range
/// (dot, label, and the main line's own segments through them) stay
/// hollow no matter how far [currentStep] has gotten — a bypassed path
/// never actually visits them, so only the loop gets to show as done
/// there.
class OnboardingProgressDots extends StatelessWidget {
  const OnboardingProgressDots({
    super.key,
    required this.currentStep,
    this.bypass,
  });

  final int currentStep;
  final ({int from, int to})? bypass;

  static const stepCount = 5;
  static const _labels = ['tutorial', 'Q1', 'account', 'Q2', 'finish'];
  static const _dotSize = 16.0;

  /// How far below the main line the bypass loop hangs — deep enough to
  /// read as a clear loop rather than a second line running alongside
  /// the first.
  static const _bypassOffset = 16.0;

  /// A step strictly between [bypass]'s `from` and `to` was never
  /// actually reached on a bypassed path — the loop skips over it
  /// entirely — so its dot and label stay hollow even once
  /// [currentStep] has passed it.
  bool _isSkipped(int step) =>
      bypass != null && step > bypass!.from && step < bypass!.to;

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
                      color: !_isSkipped(step) && step <= currentStep
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
                                  color:
                                      !_isSkipped(step) && step <= currentStep
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
/// [bypass]'s `from` step, across, up into its `to` step. The two lines
/// are independent, sharing only the two points the loop drops from and
/// rises back into — except that the main line's own segments between
/// `from` and `to` stay hollow regardless of [currentStep], since a
/// bypassed path never actually walks that stretch; only the loop gets
/// to show as done there.
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
    final bypass = this.bypass;
    for (var step = 2; step <= OnboardingProgressDots.stepCount; step++) {
      // A segment the bypass skips over was never actually walked, so
      // it stays hollow even once currentStep has passed it — only the
      // loop below gets to claim that ground as "done".
      final skipped =
          bypass != null && step - 1 >= bypass.from && step <= bypass.to;
      final paint = Paint()
        ..color = !skipped && step <= currentStep ? activeColor : inactiveColor
        ..strokeWidth = _strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(_centerX(step - 1), _lineY),
        Offset(_centerX(step), _lineY),
        paint,
      );
    }

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
          // Same rule as the main line's segments: only lit once the
          // reader has actually reached that far, not just because a
          // bypass exists. Shown from early in the shortcut (`from`
          // onward), this stays hollow until `to` is reached.
          ..color = bypass.to <= currentStep ? activeColor : inactiveColor
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
