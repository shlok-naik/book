import 'package:flutter/material.dart';

import '../widgets/natural_language_wall.dart';
import '../widgets/tier_label.dart';
import 'buttons_tutorial_page.dart';
import 'goodreads_prompt_page.dart';
import 'tutorial_step_page.dart';

/// After [SpeakFreelyPage]: it isn't only progress — shelves, tags, series
/// and comments can all be made and used from the add tab in plain words.
class AnythingPossiblePage extends StatelessWidget {
  const AnythingPossiblePage({super.key});

  @override
  Widget build(BuildContext context) {
    return TutorialStepPage(
      topContent: const NaturalLanguageWall(rows: NaturalLanguageWall.organise),
      tier: OnboardingTier.free,
      heading: 'anything is possible',
      description: const TourSteps(
        intro:
            'everything you can tap, you can say. organise your whole library '
            'from the add tab without leaving the keyboard.',
        [
          ('shelves', '"make a shelf called summer reads"'),
          ('tags', '"tag dune as sci-fi"'),
          ('series', '"put dune messiah in the dune series as #2"'),
          ('comments', '"note on dune: the ending got me"'),
          ('moves', '"move dune to summer reads"'),
        ],
        outro:
            'custom shelves and more than a few tags and series are part of '
            'cactus pro.',
      ),
      onContinue: () => Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'onboarding_goodreads_prompt'),
          builder: (_) => const GoodreadsPromptPage(),
        ),
      ),
    );
  }
}
