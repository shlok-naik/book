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
      topContent: const ExpressIllustration(),
      tier: OnboardingTier.free,
      heading: 'express yourself',
      description: const TourSteps([
        ('⭐', 'rate a finished book, half stars included'),
        ('🏷️', 'tag books however you think of them — cosy, reread, 2am'),
        ('🗂️', 'make your own shelves beside reading, to read and finished'),
      ]),
      onContinue: () => Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'onboarding_customisation_tour'),
          builder: (_) => const CustomisationTourPage(),
        ),
      ),
    );
  }
}
