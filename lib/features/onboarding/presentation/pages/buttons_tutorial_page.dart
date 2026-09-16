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
      description: const TourSteps(
        intro:
            'cactus keeps track of every book you read, and the basics never '
            'take more than a tap or two.',
        [
          (
            'start',
            'find a book on the search tab and tap want to read, or reading '
                'if you have already begun.',
          ),
          (
            'update',
            'open the book and type the page you are on. the percentage and '
                'your progress bar follow along.',
          ),
          (
            'finish',
            'move it to your finished shelf. the last page and the date are '
                'filled in for you.',
          ),
        ],
        outro:
            'hold a book on any shelf to move it somewhere else or drop it in '
            'the bin.',
      ),
      onContinue: () => Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'onboarding_express_yourself'),
          builder: (_) => const ExpressYourselfPage(),
        ),
      ),
    );
  }
}

/// The tour pages' body: an optional [intro], a bulleted list of a bold
/// label and what it means, and an optional [outro].
class TourSteps extends StatelessWidget {
  const TourSteps(this.steps, {super.key, this.intro, this.outro});

  final List<(String, String)> steps;
  final String? intro;
  final String? outro;

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
        for (final (label, text) in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: AppSpacing.sm),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: colors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$label  ',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            color: colors.primaryText,
                          ),
                        ),
                        TextSpan(text: text),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (outro case final outro?) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(outro),
        ],
      ],
    );
  }
}
