import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../widgets/day_detail_sheet.dart';
import '../widgets/month_dot_grid.dart';

/// The year, broken into months, each a grid of day-dots — a structured
/// take on the inspiration's single 365-dot grid, for reading streaks.
/// Tapping a day opens a smaller sheet for that date.
class StreaksPage extends StatelessWidget {
  const StreaksPage({super.key});

  /// Shared by every month block — the gap above its dot row (from the
  /// label) and the gap below it (to the next month's label) match.
  /// Kept small on purpose: with all twelve months on screen at once
  /// (see [build] — no scrolling), this is what actually has room to
  /// give.
  static const _rowGap = 6.0;

  /// Small trailing margin below December, on top of [_barFootprint] —
  /// so the last row of dots doesn't sit flush against the floating bar.
  static const _edgeGap = 6.0;

  /// The floating bottom bar's total footprint (bar height + its own
  /// gap + the name label + its margin from the screen edge) — see
  /// bottom_switcher.dart's _outerHeight (70) and root_shell.dart.
  static const _barFootprint = 108.0;

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    final colors = context.colors;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          // Same top/left inset as the library and profile pages' own
          // headers, so all three sit at the exact same position.
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            0,
          ),
          // The whole year fits on one screen, no scrolling — every
          // month's own gaps (see [_rowGap]) are kept tight so all
          // twelve, plus the header, stay above the floating bar.
          child: Padding(
            padding: const EdgeInsets.only(bottom: _edgeGap + _barFootprint),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Same large section-label style as the library page's
                // own "library" header — jetBrainsMono, not a one-off.
                Text(
                  'streak',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
                // Same gap as library's own "library" header down to
                // its first section label ("reading") — that gap is
                // _Header's own md bottom padding *plus* _SectionLabel's
                // own sm bottom padding stacked on top of it, so lg
                // (24) is the true total, not md alone.
                const SizedBox(height: AppSpacing.lg),
                for (var i = 1; i <= 12; i++) ...[
                  if (i > 1) const SizedBox(height: _rowGap),
                  MonthDotGrid(
                    month: i,
                    year: year,
                    labelGap: _rowGap,
                    onDayTap: (date) => showDayDetailSheet(context, date),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
