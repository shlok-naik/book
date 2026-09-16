import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../widgets/tier_label.dart';
import 'speed_up_prompt_page.dart';
import 'tutorial_step_page.dart';

/// The first tutorial step: cactus works by tapping. Search for a book and
/// press "want to read"; open a book to change its shelf, progress, rating
/// or read it again; hold a book on a shelf to move it or drop it in the
/// bin. Commands come after, and only if the reader wants them
/// ([SpeedUpPromptPage]).
class ButtonsTutorialPage extends StatelessWidget {
  const ButtonsTutorialPage({super.key});

  @override
  Widget build(BuildContext context) {
    return TutorialStepPage(
      topContent: const _ButtonsIllustration(),
      tier: OnboardingTier.free,
      heading: 'just tap',
      description: const _Copy(),
      onContinue: () => Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'onboarding_speed_up'),
          builder: (_) => const SpeedUpPromptPage(),
        ),
      ),
    );
  }
}

const _steps = [
  ('🔍', 'find a book in search and press want to read'),
  ('📖', 'tap a book to change its shelf, page or rating'),
  ('✋', 'hold a book on a shelf to move it or bin it'),
];

class _Copy extends StatelessWidget {
  const _Copy();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('everything in cactus is a button away:'),
        const SizedBox(height: AppSpacing.sm),
        for (final (emoji, text) in _steps)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$emoji  '),
                Expanded(
                  child: Text(
                    text,
                    style: GoogleFonts.inter(color: colors.primaryText),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A few of the app's own buttons, drawn the way they look in the app.
class _ButtonsIllustration extends StatelessWidget {
  const _ButtonsIllustration();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget pill(String label, {bool filled = false, IconData? icon}) =>
        Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            color: filled ? colors.accent : colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: colors.accent),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 18,
                  color: filled ? colors.background : colors.accent,
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(
                label,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14,
                  color: filled ? colors.background : colors.accent,
                ),
              ),
            ],
          ),
        );

    return ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          pill('want to read', filled: true),
          pill('move to shelf', icon: Icons.drive_file_move_outline),
          pill('read again', icon: Icons.replay),
          pill('remove', icon: Icons.delete_outline),
        ],
      ),
    );
  }
}
