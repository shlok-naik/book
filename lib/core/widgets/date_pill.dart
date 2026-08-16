import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// The filled cobalt date chip — shared wherever a date needs to appear.
/// Defaults to today; pass [date] to label any other day. Today,
/// yesterday, and tomorrow read as words instead of the usual
/// "weekday, dd.mm" format.
class DatePill extends StatelessWidget {
  const DatePill({super.key, this.date});

  final DateTime? date;

  static const _weekdays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

  static String _label(DateTime date) {
    final today = DateTime.now();
    final day = DateTime(date.year, date.month, date.day);
    final todayDay = DateTime(today.year, today.month, today.day);
    final diff = day.difference(todayDay).inDays;

    if (diff == 0) return 'today';
    if (diff == -1) return 'yesterday';
    if (diff == 1) return 'tomorrow';

    final weekday = _weekdays[date.weekday - 1];
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    return '$weekday, $dd.$mm';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.accent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        _label(date ?? DateTime.now()),
        style: GoogleFonts.jetBrainsMono(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}
