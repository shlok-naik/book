import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../widgets/tier_label.dart';
import '../widgets/tour_illustrations.dart';
import 'express_yourself_page.dart';
import 'tutorial_step_page.dart';

/// The tour's first step: the basics — start, update and finish a book —
/// are each one tap. Followed by [ExpressYourselfPage].
class ButtonsTutorialPage extends StatelessWidget {
  const ButtonsTutorialPage({super.key});

  @override
  Widget build(BuildContext context) {
    return TutorialStepPage(
      topContent: const TapIllustration(),
      tier: OnboardingTier.free,
      heading: 'just a tap away',
      description: const TourSteps([
        ('▶️', 'start: find a book in search, tap want to read or reading'),
        ('📖', "update: open a book and type the page you're on"),
        ('✅', 'finish: move it to finished — the page fills itself in'),
      ]),
      onContinue: () => Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'onboarding_express_yourself'),
          builder: (_) => const ExpressYourselfPage(),
        ),
      ),
    );
  }
}

/// A short emoji-bulleted list — the tour pages' body.
class TourSteps extends StatelessWidget {
  const TourSteps(this.steps, {super.key, this.intro});

  final List<(String, String)> steps;
  final String? intro;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (intro case final intro?) ...[
          Text(intro),
          const SizedBox(height: AppSpacing.sm),
        ],
        for (final (emoji, text) in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$emoji  '),
                Expanded(
                  child: Text(
                    text,
                    style: GoogleFonts.inter(color: colors.primaryText),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
