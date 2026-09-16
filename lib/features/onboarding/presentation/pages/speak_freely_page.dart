import 'package:flutter/material.dart';

import '../widgets/natural_language_wall.dart';
import '../widgets/tier_label.dart';
import 'anything_possible_page.dart';
import 'buttons_tutorial_page.dart';
import 'tutorial_step_page.dart';

/// Shown when the reader wants to speed things up: the add tab reads plain
/// sentences — typos and several books at once included. No syntax to
/// learn. Followed by [AnythingPossiblePage].
class SpeakFreelyPage extends StatelessWidget {
  const SpeakFreelyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return TutorialStepPage(
      topContent: const NaturalLanguageWall(),
      tier: OnboardingTier.free,
      heading: 'speak how you want',
      description: const TourSteps(
        intro:
            'on the add tab, just say what happened, the way you would tell a '
            'friend. cactus works out the rest.',
        [
          ('start', '"started the shining yesterday"'),
          ('update', '"halfway through dune"'),
          ('finish', '"finished circe last night, loved it, 5 stars"'),
          ('queue', '"add doctor sleep to my to read"'),
        ],
        outro:
            'typos, dates and several books in one sentence all work. if a '
            'book could be more than one, cactus asks which.',
      ),
      onContinue: () => Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'onboarding_anything_possible'),
          builder: (_) => const AnythingPossiblePage(),
        ),
      ),
    );
  }
}
