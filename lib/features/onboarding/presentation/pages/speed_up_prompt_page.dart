import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../paywall/presentation/widgets/soft_pill_button.dart';
import '../widgets/half_sheet_scaffold.dart';
import '../widgets/tour_illustrations.dart';
import 'goodreads_prompt_page.dart';
import 'speak_freely_page.dart';

/// Asked after the tour: does the reader want the faster way? "yes, show
/// me" shows the add tab's plain-sentence logging ([SpeakFreelyPage]); "no
/// thanks" skips straight to [GoodreadsPromptPage].
class SpeedUpPromptPage extends StatelessWidget {
  const SpeedUpPromptPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return HalfSheetScaffold(
      showBackButton: true,
      topContent: const TourIcon(Icons.bolt_outlined),
      cardChild: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'want to speed it up?',
            style: GoogleFonts.ebGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'say what you read in plain words instead of tapping. totally '
            'optional.',
            style: GoogleFonts.inter(
              fontSize: 16,
              height: 1.5,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SoftPillButton(
            label: 'yes, show me',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                settings: const RouteSettings(name: 'onboarding_speak_freely'),
                builder: (_) => const SpeakFreelyPage(),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                settings: const RouteSettings(name: 'onboarding_goodreads'),
                builder: (_) => const GoodreadsPromptPage(),
              ),
            ),
            child: Text(
              'no thanks',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: colors.secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
