import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import 'soft_pill_button.dart';

/// A plain, static "you're done" beat — an icon, a big heading, a
/// muted line of copy, and a single button — shared by every
/// onboarding screen whose only job is to confirm something just
/// happened (a purchase, a finished profile) before moving on.
/// Deliberately not built on [HalfSheetScaffold] like the rest of
/// onboarding (no split top/bottom, no progress dots): each of these
/// is a beat on its own, not another step in a sequence.
class CelebrationPage extends StatelessWidget {
  const CelebrationPage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.onContinue,
  });

  final Widget icon;
  final String title;
  final String message;
  final String buttonLabel;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            children: [
              const Spacer(),
              Center(child: icon),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title,
                style: GoogleFonts.ebGaramond(
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  height: 1.5,
                  color: colors.secondaryText,
                ),
              ),
              const Spacer(),
              SoftPillButton(
                label: buttonLabel,
                backdrop: SoftPillBackdrop.background,
                onPressed: onContinue,
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}
