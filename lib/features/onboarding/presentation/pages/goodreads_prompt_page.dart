import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../library_transfer/presentation/pages/import_page.dart';
import '../../../paywall/presentation/widgets/soft_pill_button.dart';
import '../widgets/half_sheet_scaffold.dart';
import '../widgets/tour_illustrations.dart';
import 'theme_preference_page.dart';

/// Sits right after the tutorial pages, before "pick a look" — a reader
/// coming from Goodreads is most likely to think of that the moment the
/// tutorial's done explaining how cactus works.
///
/// Importing here is free — this is the one place a fresh install can
/// bring a whole library over before the reader has ever paid for
/// anything. Once onboarding ends, the same import (settings' `your
/// library` row) is a cactus pro feature. "import my library" pushes the
/// real [ImportPage] directly, no paywall; "not now" skips it.
class GoodreadsPromptPage extends StatelessWidget {
  const GoodreadsPromptPage({super.key});

  static Route<void> _nextRoute() => MaterialPageRoute(
    settings: const RouteSettings(name: 'onboarding_theme_preference'),
    builder: (_) => const ThemePreferencePage(),
  );

  Future<void> _import(BuildContext context) async {
    await openGoodreadsImport(context);
    if (!context.mounted) return;
    await Navigator.of(context).push(_nextRoute());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return HalfSheetScaffold(
      showBackButton: true,
      topContent: const TourIcon(Icons.local_library_outlined),
      cardChild: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'coming from goodreads?',
            style: GoogleFonts.ebGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'if you\'ve been tracking your reading there, we can bring '
            'your whole library over — shelves, ratings, everything.',
            style: GoogleFonts.inter(
              fontSize: 16,
              height: 1.5,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SoftPillButton(
            label: 'import my library',
            onPressed: () => _import(context),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            onPressed: () => Navigator.of(context).push(_nextRoute()),
            child: Text(
              'not now',
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
