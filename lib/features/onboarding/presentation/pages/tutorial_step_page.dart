import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../paywall/presentation/widgets/soft_pill_button.dart';
import '../widgets/half_sheet_scaffold.dart';
import '../widgets/tier_label.dart';
import 'goodreads_prompt_page.dart';

/// One step of the post-welcome tutorial, styled after Pushr's
/// onboarding pattern: whatever demonstrates the step sits in the top
/// half of a plain background, and a rounded-top card rises to fill
/// exactly the bottom half with a heading, a description, and a single
/// continue action.
///
/// This is the shared template — [topContent] is the only thing that
/// changes between steps (a mocked-up command for "add a book", …), so
/// each concrete step is just a call to this widget with different
/// content rather than its own page class. The bottom-sheet shape
/// itself lives in [HalfSheetScaffold], shared with the rest of the
/// onboarding flow so every screen matches.
class TutorialStepPage extends StatelessWidget {
  const TutorialStepPage({
    super.key,
    required this.topContent,
    required this.heading,
    required this.description,
    required this.onContinue,
    this.buttonLabel = 'continue',
    this.progressStep,
    this.tier,
    this.tourStep,
  });

  /// How many pages the tour has.
  static const tourLength = 4;

  /// Which page (1–[tourLength]) of the tour this is. Shown in words ("2 of
  /// 4") beside a "skip tour" link — dots alone don't tell everyone how far
  /// there is to go, or that they don't have to go at all.
  final int? tourStep;

  /// What demonstrates this step — placed centered in the top half.
  final Widget topContent;

  final String heading;

  /// The step's body. A plain `Text` for a short blurb, or something
  /// richer — a command list, an inline example — for a step that
  /// needs more room to explain itself. Inherits the shared body style
  /// (secondary color, 14px, 1.5 line height) via [DefaultTextStyle],
  /// so a plain `Text` doesn't need to restate it, though any `Text`
  /// inside can still override individual pieces (bold a word, italicize
  /// a note) as needed.
  final Widget description;

  final VoidCallback onContinue;
  final String buttonLabel;

  /// Forwarded to [HalfSheetScaffold] — which step (1-5) of the
  /// tutorial → reading goal → second question → account → finish
  /// sequence this is.
  final int? progressStep;

  /// Which plan this step describes, shown as a [TierLabel] above the
  /// heading. Null shows nothing — for a step that isn't about a plan.
  final OnboardingTier? tier;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final tourStep = this.tourStep;
    return HalfSheetScaffold(
      showBackButton: true,
      topContent: topContent,
      progressStep: progressStep,
      cardChild: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tourStep != null) ...[
            Row(
              children: [
                Text(
                  '$tourStep of $tourLength',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: colors.secondaryText,
                  ),
                ),
                const Spacer(),
                TextButton(
                  key: const ValueKey('tour-skip'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      settings: const RouteSettings(
                        name: 'onboarding_goodreads',
                      ),
                      builder: (_) => const GoodreadsPromptPage(),
                    ),
                  ),
                  child: Text(
                    'skip tour',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.primaryText,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          if (tier case final tier?) ...[
            Align(alignment: Alignment.centerLeft, child: TierLabel(tier)),
            const SizedBox(height: AppSpacing.sm),
          ],
          Text(
            heading,
            style: GoogleFonts.ebGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          DefaultTextStyle.merge(
            style: GoogleFonts.inter(
              fontSize: 16,
              height: 1.5,
              color: colors.secondaryText,
            ),
            child: description,
          ),
          const SizedBox(height: AppSpacing.lg),
          SoftPillButton(label: buttonLabel, onPressed: onContinue),
        ],
      ),
    );
  }
}
