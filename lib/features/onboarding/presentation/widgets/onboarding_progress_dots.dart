import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// The step indicator shown across the post-tutorial onboarding flow:
/// tutorial → Q1 → Q2 → account → finish. [currentStep] (1-5) and every
/// step before it are drawn filled, with a filled connecting line
/// leading into them; the rest are hollow. Never shown on the tutorial
/// page itself — only from Q1 onward.
class OnboardingProgressDots extends StatelessWidget {
  const OnboardingProgressDots({super.key, required this.currentStep});

  final int currentStep;

  static const stepCount = 5;
  static const _labels = ['tutorial', 'Q1', 'Q2', 'account', 'finish'];
  static const _dotSize = 16.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            // Each dot sits centered in an equal-width slot — the line
            // below spans exactly center-to-center across those slots,
            // computed from the actual slot width rather than guessed,
            // so it lines up regardless of how wide the labels are.
            final slotWidth = constraints.maxWidth / stepCount;

            return SizedBox(
              height: _dotSize,
              child: Stack(
                children: [
                  // Drawn behind the dots and spanning center-to-center,
                  // so each dot's solid fill covers the line where they
                  // overlap — it runs straight through every dot instead
                  // of stopping short at the circle's edge.
                  Positioned(
                    top: (_dotSize - 2) / 2,
                    left: slotWidth / 2,
                    right: slotWidth / 2,
                    child: Row(
                      children: [
                        for (var step = 2; step <= stepCount; step++)
                          Expanded(
                            child: Container(
                              height: 2,
                              color: step <= currentStep ? colors.accent : colors.divider,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      for (var step = 1; step <= stepCount; step++)
                        Expanded(
                          child: Center(
                            child: Container(
                              width: _dotSize,
                              height: _dotSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: step <= currentStep ? colors.accent : colors.divider,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            for (var step = 1; step <= stepCount; step++)
              Expanded(
                child: Center(
                  child: Text(
                    _labels[step - 1],
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: step <= currentStep ? colors.primaryText : colors.secondaryText,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
