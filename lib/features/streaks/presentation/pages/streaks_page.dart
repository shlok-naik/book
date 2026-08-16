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
  static const _rowGap = 13.0;

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xxl,
            AppSpacing.xl,
            0,
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 130),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 1; i <= 12; i++)
                  MonthDotGrid(
                    month: i,
                    year: year,
                    labelGap: _rowGap,
                    onDayTap: (date) => showDayDetailSheet(context, date),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
