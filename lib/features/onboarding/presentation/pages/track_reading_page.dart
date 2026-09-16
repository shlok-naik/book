import 'package:flutter/material.dart';

import '../widgets/tier_label.dart';
import '../widgets/tour_illustrations.dart';
import 'buttons_tutorial_page.dart';
import 'speed_up_prompt_page.dart';
import 'tutorial_step_page.dart';

/// The tour's fourth step: the stats tab.
class TrackReadingPage extends StatelessWidget {
  const TrackReadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return TutorialStepPage(
      topContent: const StatsIllustration(),
      tier: OnboardingTier.free,
      heading: 'track your reading',
      description: const TourSteps([
        ('🎯', 'a yearly goal, and how far along you are'),
        ('🔥', 'every day you read, on a heatmap of the year'),
        ('📊', 'books and pages read, your shelves at a glance'),
      ]),
      onContinue: () => Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'onboarding_speed_up'),
          builder: (_) => const SpeedUpPromptPage(),
        ),
      ),
    );
  }
}
