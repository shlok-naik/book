import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../paywall/presentation/widgets/soft_pill_button.dart';
import '../widgets/half_sheet_scaffold.dart';
import 'add_book_tutorial_page.dart';
import 'goodreads_prompt_page.dart';

/// Asked right after the buttons tutorial: does the reader want the faster
/// way? "yes" walks the command tutorials ([AddBookTutorialPage] onwards);
/// "no thanks" skips them straight to [GoodreadsPromptPage]. Either way the
/// commands stay one tap away in settings' help section.
class SpeedUpPromptPage extends StatelessWidget {
  const SpeedUpPromptPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return HalfSheetScaffold(
      showBackButton: true,
      topContent: const Text('⚡', style: TextStyle(fontSize: 96)),
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
            'type short commands like "finish dune" instead of tapping. '
            "totally optional — you'll find them in settings later too.",
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.5,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SoftPillButton(
            label: 'yes, show me',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                settings: const RouteSettings(
                  name: 'onboarding_add_book_tutorial',
                ),
                builder: (_) => const AddBookTutorialPage(),
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
