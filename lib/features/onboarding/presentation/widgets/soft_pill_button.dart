import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';

/// Which backdrop a [SoftPillButton] sits on — the shell color needs to
/// read against it, so this picks the other tone in the pair rather
/// than always reaching for the same one.
enum SoftPillBackdrop {
  /// The welcome screen's plain scaffold, colored [AppColors.background].
  background,

  /// [HalfSheetScaffold]'s card, colored [AppColors.surface] — every
  /// other onboarding page's button lives here.
  surface,
}

/// The bare pill treatment shared with the bottom tab bar: a shell with
/// a soft shadow (or, where a shadow wouldn't read, a hairline border)
/// around an inset, tint-filled pill. [child] is laid over that inner
/// pill, which is a [Material] — so an `InkWell` child gets ripples for
/// free.
///
/// Split out of [SoftPillButton] so controls that aren't a plain
/// labelled button — the paywall's free-trial toggle, for one — can
/// wear the exact same treatment instead of re-deriving it and slowly
/// drifting out of step.
class SoftPillShell extends StatelessWidget {
  const SoftPillShell({
    super.key,
    required this.child,
    this.tint,
    this.backdrop = SoftPillBackdrop.surface,
  });

  final Widget child;

  /// Fill color for the inner pill (at 22% alpha) — defaults to
  /// [AppColors.accent].
  final Color? tint;

  final SoftPillBackdrop backdrop;

  static const inset = AppSpacing.xs;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final radius = BorderRadius.circular(AppRadius.pill);
    final tintColor = tint ?? colors.accent;

    final Color shellColor;
    final bool needsBorder;
    switch (backdrop) {
      case SoftPillBackdrop.background:
        // Mirrors the bottom tab bar exactly: it floats on this same
        // background, defined by shadow alone in light mode and by the
        // lighter "surface" tone in dark mode.
        shellColor = isLight ? colors.background : colors.surface;
        needsBorder = false;
      case SoftPillBackdrop.surface:
        // The card underneath is already `surface` — reusing it here
        // would make the shell disappear, so this reaches for
        // `background` instead. That reads fine against a shadow in
        // light mode, but background sits *darker* than surface in
        // dark mode (a subtle inset rather than a raised shell), so a
        // hairline border stands in for the shadow there.
        shellColor = colors.background;
        needsBorder = !isLight;
    }

    return Container(
      padding: const EdgeInsets.all(inset),
      decoration: BoxDecoration(
        color: shellColor,
        borderRadius: radius,
        border: needsBorder ? Border.all(color: colors.divider) : null,
        boxShadow: isLight
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: tintColor.withValues(alpha: 0.22),
        borderRadius: radius,
        child: child,
      ),
    );
  }
}

/// A labelled button in the app's pill treatment — [SoftPillShell] with
/// a centered, [tint]-colored label on top.
class SoftPillButton extends StatelessWidget {
  const SoftPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.tint,
    this.backdrop = SoftPillBackdrop.surface,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Fill/text color for the inner pill — defaults to [AppColors.accent].
  /// [HaveWeMetPage]'s "no" passes [AppColors.secondaryText] so it reads
  /// as the non-default choice sitting next to "yes".
  final Color? tint;

  final SoftPillBackdrop backdrop;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(AppRadius.pill);
    final tintColor = tint ?? colors.accent;

    return SoftPillShell(
      tint: tint,
      backdrop: backdrop,
      child: InkWell(
        onTap: onPressed,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: tintColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
