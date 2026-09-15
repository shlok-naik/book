import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';

/// Which plan an onboarding step (or one command on it) belongs to.
enum OnboardingTier { free, pro }

/// A small chip naming the plan an onboarding step belongs to — worn above
/// the heading of every tutorial step and the Goodreads prompt, so the
/// point where the tour stops describing what a reader already has and
/// starts describing what cactus pro adds is visible at a glance rather
/// than buried in a sentence of body copy.
///
/// The two tiers are deliberately unequal: "free" is an outline in the
/// secondary text color (it's the baseline, nothing to call attention
/// to), "cactus pro" is filled with the accent — the same filled-badge
/// language the paywall's own PRO badge and the membership card use.
class TierLabel extends StatelessWidget {
  const TierLabel(this.tier, {super.key});

  final OnboardingTier tier;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isPro = tier == OnboardingTier.pro;

    return Semantics(
      label: isPro ? 'Cactus pro feature' : 'Included free',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 3,
        ),
        decoration: BoxDecoration(
          color: isPro ? colors.accent : null,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: isPro ? colors.accent : colors.secondaryText,
          ),
        ),
        child: Text(
          isPro ? 'cactus pro' : 'free',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: isPro ? colors.background : colors.secondaryText,
          ),
        ),
      ),
    );
  }
}

/// A one-line "pro" marker for a single command inside an otherwise-free
/// command list (e.g. `make shelf` on the tags step). Text rather than a
/// chip so it doesn't make the row taller than its neighbours.
class ProMarker extends StatelessWidget {
  const ProMarker({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      '  · pro',
      style: GoogleFonts.jetBrainsMono(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: context.colors.accent,
      ),
    );
  }
}
