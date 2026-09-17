import 'package:flutter/material.dart';

import '../widgets/tier_label.dart';
import '../widgets/tour_illustrations.dart';
import 'buttons_tutorial_page.dart';
import 'customisation_tour_page.dart';
import 'tutorial_step_page.dart';

/// The tour's second step: rate, tag and shelve books your own way.
class ExpressYourselfPage extends StatelessWidget {
  const ExpressYourselfPage({super.key});

  @override
  Widget build(BuildContext context) {
    return TutorialStepPage(
      tourStep: 2,
      topContent: const ExpressIllustration(),
      tier: OnboardingTier.free,
      heading: 'express yourself',
      description: const TourSteps(
        intro:
            'a book is more than a title on a list. say what it meant to you, '
            'right on its page.',
        [
          ('rate', 'give a finished book up to five stars, halves included.'),
          (
            'tag',
            'label books however you think of them: cosy, reread, 2am, '
                'summer. find them again by tag later.',
          ),
          (
            'shelves',
            'make your own shelves next to reading, to read and finished, and '
                'group a series together.',
          ),
          ('comment', 'jot down a thought, or why you gave up on a book.'),
        ],
      ),
      onContinue: () => Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'onboarding_customisation_tour'),
          builder: (_) => const CustomisationTourPage(),
        ),
      ),
    );
  }
}
