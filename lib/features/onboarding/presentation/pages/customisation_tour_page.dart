import 'package:flutter/material.dart';

import '../widgets/tier_label.dart';
import '../widgets/tour_illustrations.dart';
import 'buttons_tutorial_page.dart';
import 'track_reading_page.dart';
import 'tutorial_step_page.dart';

/// The tour's third step, cactus pro: themes, launcher icons and fonts.
class CustomisationTourPage extends StatelessWidget {
  const CustomisationTourPage({super.key});

  @override
  Widget build(BuildContext context) {
    return TutorialStepPage(
      tourStep: 3,
      topContent: const CustomiseIllustration(),
      tier: OnboardingTier.pro,
      heading: 'cactus, how you want it',
      description: const TourSteps(
        intro:
            'with cactus pro the whole app bends to your taste, from your home '
            'screen to the last page.',
        [
          (
            'themes',
            'pick the accent colour the whole app wears, in light and dark.',
          ),
          ('icons', 'choose from sixteen launcher icons for your home screen.'),
          (
            'fonts',
            'set every screen like a paperback, a typewriter or something '
                'more robotic.',
          ),
        ],
      ),
      onContinue: () => Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'onboarding_track_reading'),
          builder: (_) => const TrackReadingPage(),
        ),
      ),
    );
  }
}
