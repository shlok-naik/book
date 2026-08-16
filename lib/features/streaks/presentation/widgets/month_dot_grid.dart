import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';

/// One labeled month block: name, then a dot per day laid out in a
/// calendar-width grid — the structured, per-month take on the
/// inspiration's single continuous 365-dot grid.
class MonthDotGrid extends StatelessWidget {
  const MonthDotGrid({
    super.key,
    required this.month,
    required this.year,
    required this.labelGap,
  });

  final int month;
  final int year;

  /// Space between the month label and its dot row — kept equal to the
  /// gap below the row (to the next month's label) by the caller.
  final double labelGap;

  static const _monthNames = [
    'january', 'february', 'march', 'april', 'may', 'june',
    'july', 'august', 'september', 'october', 'november', 'december',
  ];

  static const _dotDiameter = 4.0;

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
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.secondaryText,
          ),
        ),
        SizedBox(height: labelGap),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: List.generate(
            daysInMonth,
            (_) => Container(
              width: _dotDiameter,
              height: _dotDiameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.accent.withValues(alpha: 0.35),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
