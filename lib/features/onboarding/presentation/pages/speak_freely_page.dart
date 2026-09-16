import 'package:flutter/material.dart';

import '../widgets/natural_language_wall.dart';
import '../widgets/tier_label.dart';
import 'buttons_tutorial_page.dart';
import 'goodreads_prompt_page.dart';
import 'tutorial_step_page.dart';

/// Shown when the reader wants to speed things up: the add tab reads plain
/// sentences — the free on-device parser, typos and several books at once
/// included. No command syntax to learn.
class SpeakFreelyPage extends StatelessWidget {
  const SpeakFreelyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return TutorialStepPage(
      topContent: const NaturalLanguageWall(),
      tier: OnboardingTier.free,
      heading: 'speak how you want',
      description:
          const TourSteps(intro: 'on the add tab, just say what happened:', [
            ('💬', '"started the shining yesterday"'),
            ('📖', '"halfway through dune, gave up on circe"'),
            ('✨', 'typos, dates and several books at once all work'),
          ]),
      onContinue: () => Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'onboarding_goodreads_prompt'),
          builder: (_) => const GoodreadsPromptPage(),
        ),
      ),
    );
  }
}
