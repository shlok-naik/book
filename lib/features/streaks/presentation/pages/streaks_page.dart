import 'package:flutter/material.dart';

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
  static const _rowGap = 9.0;

  /// The same fixed margin above January and below December — computed
  /// directly rather than left to auto-distribution, which measures
  /// "gap to the top of the page" and "gap to the floating bottom bar"
  /// as two very different quantities and can't equalize them on its own.
  static const _edgeGap = 6.0;

  /// The floating bottom bar's total footprint (bar height + its own
  /// gap + the name label + its margin from the screen edge) — see
  /// bottom_switcher.dart's _outerHeight (70) and root_shell.dart.
  static const _barFootprint = 108.0;

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            _edgeGap,
            AppSpacing.xl,
            0,
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: _edgeGap + _barFootprint),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
