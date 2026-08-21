import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/day_symbol.dart';
import 'day_symbol_mark.dart';

/// One labeled month block: name, then a dot per day laid out in a
/// calendar-width grid — the structured, per-month take on the
/// inspiration's single continuous 365-dot grid. Tapping anywhere in the
/// row opens the nearest day (the dots are too small to hit individually).
///
/// Every day sits on one continuous horizontal line — a line-only day is
/// just that line at full strength, a start is a hollow circle sitting
/// on it, and a finish is a closed circle — so consecutive days read as
/// one connected streak rather than isolated marks.
class MonthDotGrid extends StatelessWidget {
  const MonthDotGrid({
    super.key,
    required this.month,
    required this.year,
    required this.labelGap,
    required this.onDayTap,
    this.symbolFor,
  });

  final int month;
  final int year;

  /// Space between the month label and its dot row — kept equal to the
  /// gap below the row (to the next month's label) by the caller.
  final double labelGap;

  final ValueChanged<DateTime> onDayTap;

  /// What to draw for a given day — null (or a null return) means
  /// nothing was logged that day, so it gets a dim open circle.
  final DaySymbol? Function(DateTime date)? symbolFor;

  static const _monthNames = [
    'january',
    'february',
    'march',
    'april',
    'may',
    'june',
    'july',
    'august',
    'september',
    'october',
    'november',
    'december',
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
                ? (constraints.maxWidth - daysInMonth * _dotDiameter) /
                      (daysInMonth - 1)
                : 0.0;
            final cell = _dotDiameter + (gap < 0 ? 0 : gap);

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                final index = cell == 0
                    ? 0
                    : (details.localPosition.dx / cell).round().clamp(
                        0,
                        daysInMonth - 1,
                      );
                onDayTap(DateTime(year, month, index + 1));
              },
              child: SizedBox(
                width: double.infinity,
                height: _dotDiameter + 14,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // The connecting line every day's mark sits on, so
                    // circles read as joined to their neighboring lines
                    // rather than floating above them.
                    Container(
                      width: double.infinity,
                      height: 1.2,
                      color: colors.divider,
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < daysInMonth; i++) ...[
                          if (i > 0) SizedBox(width: gap < 0 ? 0 : gap),
                          SizedBox(
                            width: _dotDiameter,
                            height: _dotDiameter,
                            child: Center(
                              child: DaySymbolMark(
                                symbol: symbolFor?.call(
                                  DateTime(year, month, i + 1),
                                ),
                                diameter: _dotDiameter,
                                color: colors.accent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
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
