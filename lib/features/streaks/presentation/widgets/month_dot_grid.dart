import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/day_symbol.dart';
import 'day_symbol_mark.dart';

/// One labeled month block: name, then a dot per day laid out in a
/// calendar-width grid — the structured, per-month take on the
/// inspiration's single continuous 365-dot grid. Tapping anywhere in the
/// row opens the nearest day (the dots are too small to hit individually).
///
/// For a screen reader the row is not one target but [daysInMonth] of
/// them, each announcing its own date and what was logged that day. The
/// "nearest day" trick is a *visual* affordance for an 8pt dot; someone
/// navigating by swipe needs the days themselves, and the dots being too
/// small to see is exactly why they cannot aim at one.
///
/// Every day sits on one continuous horizontal line — a line-only day is
/// just that line at full strength, a start is a hollow circle sitting
/// on it, and a finish is a closed circle — so consecutive days read as
/// one connected streak rather than isolated marks.
///
/// [_dotDiameter] is sized for the narrowest supported screen (320pt):
/// a 31-day month at that width leaves ~0.3pt of gap between dots, so
/// don't raise it without re-checking that a full row still fits without
/// wrapping.
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

  static const _dotDiameter = 8.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    // Computed once per day rather than inline in the Row below, since
    // it drives both the mark drawn and the color it's drawn in.
    final daySymbols = [
      for (var i = 0; i < daysInMonth; i++)
        symbolFor?.call(DateTime(year, month, i + 1)),
    ];

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
                AppHaptics.selection();
                onDayTap(DateTime(year, month, index + 1));
              },
              child: SizedBox(
                width: double.infinity,
                height: _dotDiameter + 14,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // The connecting line between consecutive days —
                    // laid out as one segment per gap, matching the dot
                    // row's own spacing exactly, so it joins neighboring
                    // marks without ever running through a dot's own
                    // footprint (a hollow or unlogged circle is
                    // transparent in the middle, so a line drawn behind
                    // the whole row would otherwise show straight
                    // through it).
                    Row(
                      children: [
                        for (var i = 0; i < daysInMonth; i++) ...[
                          if (i > 0)
                            SizedBox(
                              width: gap < 0 ? 0 : gap,
                              height: 1.2,
                              child: ColoredBox(color: colors.divider),
                            ),
                          SizedBox(width: _dotDiameter),
                        ],
                      ],
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < daysInMonth; i++) ...[
                          if (i > 0) SizedBox(width: gap < 0 ? 0 : gap),
                          _Day(
                            date: DateTime(year, month, i + 1),
                            monthName: _monthNames[month - 1],
                            symbol: daySymbols[i],
                            diameter: _dotDiameter,
                            color: daySymbols[i] == null
                                ? colors.primaryText
                                : colors.loggedMark,
                            onTap: onDayTap,
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

/// A single day's mark, plus the screen-reader node that makes it
/// reachable. The visible hit target stays the parent row's "nearest
/// day" gesture — this adds a semantics-only action so assistive
/// technology can open a specific day directly rather than having to
/// land a tap within a few points of it.
class _Day extends StatelessWidget {
  const _Day({
    required this.date,
    required this.monthName,
    required this.symbol,
    required this.diameter,
    required this.color,
    required this.onTap,
  });

  final DateTime date;
  final String monthName;
  final DaySymbol? symbol;
  final double diameter;
  final Color color;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final happened = symbol?.spokenDescription ?? 'nothing logged';

    return Semantics(
      button: true,
      label: '$monthName ${date.day}, $happened',
      onTap: () {
        AppHaptics.selection();
        onTap(date);
      },
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: Center(
          child: DaySymbolMark(
            symbol: symbol,
            diameter: diameter,
            color: color,
            lineThickness: 1.6,
          ),
        ),
      ),
    );
  }
}
