import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../shell/presentation/pages/root_shell.dart';
import '../widgets/half_sheet_scaffold.dart';

/// Step 5 (finish) of the post-tutorial sequence — the last screen
/// before the app itself. By the time a reader gets here they're signed
/// in one way or another (anonymous account or an existing sign-in), so
/// this replaces the whole navigation stack with [RootShell] rather
/// than pushing, so none of the onboarding screens can be popped back to.
class FinishPage extends StatelessWidget {
  const FinishPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return HalfSheetScaffold(
      progressStep: 5,
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
          FilledButton(
            onPressed: () => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const RootShell()),
              (route) => false,
            ),
            style: FilledButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            child: Text("let's go", style: GoogleFonts.inter(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}
