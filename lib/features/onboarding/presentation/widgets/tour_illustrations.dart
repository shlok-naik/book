import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/platform/app_icon.dart';
import '../../../../core/theme/app_color_theme.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';

/// The drawings above the onboarding tour's cards — the app's own pieces
/// (buttons, stars, chips, swatches, a heatmap) drawn in its own colors,
/// rather than screenshots that go stale. Purely decorative, so each is
/// hidden from screen readers; the card underneath says the same thing.

/// A pill button as the app draws it.
class TourPill extends StatelessWidget {
  const TourPill(this.label, {super.key, this.filled = false, this.icon});

  final String label;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = filled ? colors.background : colors.accent;
    return Container(
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
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: GoogleFonts.jetBrainsMono(fontSize: 14, color: foreground),
          ),
        ],
      ),
    );
  }
}

/// Start, update, finish — each a single button.
class TapIllustration extends StatelessWidget {
  const TapIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return const ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TourPill('want to read', filled: true),
          SizedBox(height: AppSpacing.sm),
          TourPill('page 120 · save', icon: Icons.menu_book_outlined),
          SizedBox(height: AppSpacing.sm),
          TourPill('move to finished', icon: Icons.check_circle_outline),
        ],
      ),
    );
  }
}

/// Stars, tags and a shelf.
class ExpressIllustration extends StatelessWidget {
  const ExpressIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget chip(String label) => Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: colors.accent),
      ),
      child: Text(
        label,
        style: GoogleFonts.jetBrainsMono(fontSize: 13, color: colors.accent),
      ),
    );
    return ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 5; i++)
                Icon(
                  i < 4 ? Icons.star : Icons.star_half,
                  size: 40,
                  color: colors.accent,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            children: [chip('cosy'), chip('sci-fi'), chip('reread')],
          ),
          const SizedBox(height: AppSpacing.md),
          const TourPill('summer reads', icon: Icons.folder_open),
        ],
      ),
    );
  }
}

/// Accent swatches, launcher icons and font samples.
class CustomiseIllustration extends StatelessWidget {
  const CustomiseIllustration({super.key});

  static const _icons = [
    AppIcon.originalLight,
    AppIcon.booklinesLight,
    AppIcon.originalDark,
  ];
  static const _fonts = ['EB Garamond', 'Courier Prime', 'Orbitron'];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final theme in AppColorTheme.values.take(6))
                Container(
                  width: 30,
                  height: 30,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: theme.lightAccent,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final icon in _icons)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      icon.assetPath,
                      width: 58,
                      height: 58,
                      errorBuilder: (_, _, _) =>
                          const SizedBox(width: 58, height: 58),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final family in _fonts)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'Aa',
                    style: GoogleFonts.getFont(
                      family,
                      fontSize: 30,
                      color: colors.primaryText,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A few weeks of the stats page's reading-days heatmap.
class StatsIllustration extends StatelessWidget {
  const StatsIllustration({super.key});

  // Commands logged per day, for a pretend reader: 0 blank, 3 darkest.
  static const _weeks = [
    [0, 1, 0, 2, 1, 0, 0],
    [1, 2, 3, 1, 0, 2, 1],
    [0, 1, 2, 3, 3, 1, 0],
    [2, 0, 1, 2, 3, 2, 1],
    [1, 3, 2, 0, 1, 3, 3],
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final week in _weeks)
                Column(
                  children: [
                    for (final day in week)
                      Container(
                        width: 22,
                        height: 22,
                        margin: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: day == 0
                              ? colors.divider
                              : colors.accent.withValues(alpha: day / 3),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '12 of 20 books',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 14,
              color: colors.primaryText,
            ),
          ),
        ],
      ),
    );
  }
}
