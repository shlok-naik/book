import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';

/// One labeled month block: name, then a dot per day laid out in a
/// calendar-width grid — the structured, per-month take on the
/// inspiration's single continuous 365-dot grid. Tapping anywhere in the
/// row opens the nearest day (the dots are too small to hit individually).
class MonthDotGrid extends StatelessWidget {
  const MonthDotGrid({
    super.key,
    required this.month,
    required this.year,
    required this.labelGap,
    required this.onDayTap,
  });

  final int month;
  final int year;

  /// Space between the month label and its dot row — kept equal to the
  /// gap below the row (to the next month's label) by the caller.
  final double labelGap;

  final ValueChanged<DateTime> onDayTap;

  static const _monthNames = [
    'january', 'february', 'march', 'april', 'may', 'june',
    'july', 'august', 'september', 'october', 'november', 'december',
  ];

  static const _dotDiameter = 5.5;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final daysInMonth = DateTime(year, month + 1, 0).day;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _monthNames[month - 1],
          style: GoogleFonts.jetBrainsMono(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colors.primaryText,
          ),
        ),
        SizedBox(height: labelGap),
        LayoutBuilder(
          builder: (context, constraints) {
            // Solve for the gap that spreads every day across the full
            // width in one row — never wraps, regardless of month length
            // or screen size, at the same dot size throughout.
            final gap = daysInMonth > 1
                ? (constraints.maxWidth - daysInMonth * _dotDiameter) / (daysInMonth - 1)
                : 0.0;
            final cell = _dotDiameter + (gap < 0 ? 0 : gap);

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final index = cell == 0
                    ? 0
                    : (details.localPosition.dx / cell).round().clamp(0, daysInMonth - 1);
                onDayTap(DateTime(year, month, index + 1));
              },
              child: SizedBox(
                width: double.infinity,
                height: _dotDiameter + 14,
                child: Row(
                  children: [
                    for (var i = 0; i < daysInMonth; i++) ...[
                      if (i > 0) SizedBox(width: gap < 0 ? 0 : gap),
                      Container(
                        width: _dotDiameter,
                        height: _dotDiameter,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.accent.withValues(alpha: 0.35),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
