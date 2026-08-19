import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../shell/presentation/pages/root_shell.dart';
import '../widgets/half_sheet_scaffold.dart';
import '../widgets/soft_pill_button.dart';

/// Step 5 (finish) of the post-tutorial sequence — the last screen
/// before the app itself. By the time a reader gets here they're signed
/// in one way or another (anonymous account or an existing sign-in), so
/// this replaces the whole navigation stack with [RootShell] rather
/// than pushing, so none of the onboarding screens can be popped back to.
class FinishPage extends StatelessWidget {
  const FinishPage({super.key, this.bypass});

  /// Forwarded to the progress dots — the sign-in shortcut arrives here
  /// having skipped everything between account and finish, so it passes
  /// `(from: 3, to: 5)` to draw that shortcut alongside the ordinary
  /// line, which still runs through every dot unchanged.
  final ({int from, int to})? bypass;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return HalfSheetScaffold(
      progressStep: 5,
      bypass: bypass,
      topContent: const Text('🎉', style: TextStyle(fontSize: 96)),
      cardChild: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "you're all set",
            style: GoogleFonts.ebGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'time to start reading.',
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.5,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SoftPillButton(
            label: "let's go",
            onPressed: () => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const RootShell()),
              (route) => false,
            ),
          ),
        ],
      ),
    );
  }
}
