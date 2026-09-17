import 'package:flutter/material.dart';

import '../widgets/natural_language_wall.dart';
import '../widgets/tier_label.dart';
import 'buttons_tutorial_page.dart';
import 'goodreads_prompt_page.dart';
import 'tutorial_step_page.dart';

/// After [AnythingPossiblePage] — which showed what the free parser on the
/// device can do — this is where the pitch turns: cactus pro hands the same
/// sentence to cactus's own reading AI, which follows rambling, feelings and
/// several books at once instead of one tidy phrasing.
///
/// Free readers still get the beta parser for everything on the previous
/// screen; this page is deliberately the *pro* half of the same idea, so
/// the boundary is visible rather than discovered later.
class CactusUnderstandsPage extends StatelessWidget {
  const CactusUnderstandsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return TutorialStepPage(
      topContent: const NaturalLanguageWall(
        rows: NaturalLanguageWall.conversational,
      ),
      tier: OnboardingTier.pro,
      heading: 'cactus understands you',
      description: const TourSteps(
        intro:
            'with cactus pro, whole messy sentences go to cactus ai instead '
            'of the parser on your phone. say it how you would say it to a '
            'friend.',
        [
          ('ramble', '"finally finished dune last night, loved it, 5 stars"'),
          (
            'several at once',
            '"started circe, gave up on ulysses, and circe is a favourite"',
          ),
          ('feelings', '"remember that the ending of dune wrecked me"'),
          ('ask for a book', '"what should i read next?"'),
        ],
        outro:
            'it reads your own shelf and your own notes, so the books it '
            'picks are yours — not a stranger’s bestseller list.',
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
