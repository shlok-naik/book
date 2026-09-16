import 'package:flutter/material.dart';

import '../widgets/tier_label.dart';
import '../widgets/tour_illustrations.dart';
import 'buttons_tutorial_page.dart';
import 'track_reading_page.dart';
import 'tutorial_step_page.dart';

/// The tour's third step, and its one cactus pro page: themes, launcher
/// icons and fonts.
class CustomisationTourPage extends StatelessWidget {
  const CustomisationTourPage({super.key});

  @override
  Widget build(BuildContext context) {
    return TutorialStepPage(
      topContent: const CustomiseIllustration(),
      tier: OnboardingTier.pro,
      heading: 'cactus, how you want it',
      description: const TourSteps([
        ('🎨', 'themes: pick the accent the whole app wears'),
        ('📱', 'icons: sixteen launcher icons for your home screen'),
        ('🔤', 'fonts: from typewriter to paperback to robotic'),
      ]),
      onContinue: () => Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'onboarding_track_reading'),
          builder: (_) => const TrackReadingPage(),
        ),
      ),
    );
  }
}
