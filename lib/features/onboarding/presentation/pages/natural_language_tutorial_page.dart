import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/onboarding_profile_repository.dart';
import '../../data/session_service.dart';
import '../widgets/natural_language_wall.dart';
import 'theme_preference_page.dart';
import 'tutorial_step_page.dart';

/// Step 2 of the post-welcome sequence — the Pro-tier half of the
/// tutorial, following [AddBookTutorialPage]'s free-tier commands with
/// the natural-language alternative: the same actions, expressed as a
/// sentence, plus the feelings a reader tacks on along the way.
class NaturalLanguageTutorialPage extends StatelessWidget {
  const NaturalLanguageTutorialPage({
    super.key,
    required this.session,
    required this.profiles,
  });

  final SessionService session;
  final OnboardingProfileRepository profiles;

  @override
  Widget build(BuildContext context) {
    return TutorialStepPage(
      topContent: const NaturalLanguageWall(),
      heading: 'or just talk naturally',
      description: const _TutorialCopy(),
      onContinue: () => Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'onboarding_theme_preference'),
          builder: (_) =>
              ThemePreferencePage(session: session, profiles: profiles),
        ),
      ),
    );
  }
}

class _TutorialCopy extends StatelessWidget {
  const _TutorialCopy();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'in the Pro tier, you can use natural language to do the '
          'same actions and express emotions, which are saved in '
          'cactus and used for smart recommendations. for example, '
          'you could say:',
        ),
        const SizedBox(height: AppSpacing.sm),
        _ExampleQuote(colors: colors),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'this will start the book, update it to page 49, and save '
          'your emotion to memory (cool right?).',
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'ps. you can include typos or abbreviations in the text - '
          'cactus will understand.',
          style: GoogleFonts.inter(fontStyle: FontStyle.italic),
        ),
      ],
    );
  }
}

/// The worked natural-language example — set apart in its own tinted
/// box (the same `background`-on-`surface` contrast used throughout
/// onboarding) so it reads as a quoted example rather than more prose.
class _ExampleQuote extends StatelessWidget {
  const _ExampleQuote({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        '"i started the shining and read up to pg 49. i liked the '
        'pacing but the story was a bit confusing at some points."',
        style: GoogleFonts.ebGaramond(
          fontSize: 14,
          fontStyle: FontStyle.italic,
          height: 1.5,
          color: colors.primaryText,
        ),
      ),
    );
  }
}
