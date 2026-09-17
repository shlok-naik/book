import 'package:flutter/material.dart';

import '../widgets/tier_label.dart';
import '../widgets/tour_illustrations.dart';
import 'buttons_tutorial_page.dart';
import 'speed_up_prompt_page.dart';
import 'tutorial_step_page.dart';

/// The tour's fourth step, cactus pro: the stats tab.
class TrackReadingPage extends StatelessWidget {
  const TrackReadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return TutorialStepPage(
      tourStep: 4,
      topContent: const StatsIllustration(),
      tier: OnboardingTier.pro,
      heading: 'track your reading',
      description: const TourSteps(
        intro:
            'watch your reading add up over the year on the stats tab, with '
            'cactus pro.',
        [
          (
            'goal',
            'set how many books you want to read this year and see if you are '
                'ahead of pace.',
          ),
          (
            'reading days',
            'every day you read lights up a heatmap of the whole year.',
          ),
          (
            'insights',
            'books and pages by month, your favourite genres and tags, and '
                'how your pace is trending.',
          ),
        ],
      ),
      onContinue: () => Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'onboarding_speed_up'),
          builder: (_) => const SpeedUpPromptPage(),
        ),
      ),
    );
  }
}
