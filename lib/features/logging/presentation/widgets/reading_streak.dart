import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../library/domain/reading_event.dart';
import '../../../library/presentation/library_scope.dart';

/// The full streak readout on the add tab: a "N day streak" heading
/// over a row of the last seven days, each marked for whether anything
/// was logged — the same shape as Fable's own streak card, restyled to
/// this app's own quiet, lowercase, dot-not-emoji language, and with no
/// card chrome of its own — the streak/memory pages next door are both
/// plain journals, not boxed cards, so this sits directly on the page
/// background the same way.
///
/// Read-only, unlike Fable's tappable "I read today" button: this app
/// has no generic "I read" event to log — every `reading_events` row is
/// tied to a real command against a real book (`start`/`update <page>`/
/// `finish`/`rate`), so a button that doesn't correspond to any of those
/// would be a fake action. Typing a real command in [CommandInput] above
/// *is* how a reader marks today; this readout just shows what that's
/// already added up to.
class ReadingStreak extends StatefulWidget {
  const ReadingStreak({super.key});

  @override
  State<ReadingStreak> createState() => _ReadingStreakState();
}

class _ReadingStreakState extends State<ReadingStreak> {
  /// Null until the one load finishes (or forever, if it fails) — the
  /// card stays invisible either way, since a wrong or missing streak on
  /// a spot this quiet is worse than no card at all.
  Set<DateTime>? _loggedDays;
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final events = LibraryScope.read(context).events;
      final rows = await events.fetchForYear(DateTime.now().year);
      if (!mounted) return;
      setState(
        () => _loggedDays = {
          for (final event in rows)
            if (event.type != ReadingEventType.delete)
              _dayKey(event.occurredAt.toLocal()),
        },
      );
    } on Object {
      // Silent — see [_loggedDays]'s doc comment.
    }
  }

  static DateTime _dayKey(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  /// Consecutive local days, ending today or yesterday, in [loggedDays]
  /// — the same rule the streak journal itself uses for what counts as
  /// "logged" (a `delete` doesn't).
  static int _currentStreak(Set<DateTime> loggedDays) {
    if (loggedDays.isEmpty) return 0;

    final today = _dayKey(DateTime.now());
    var cursor = loggedDays.contains(today)
        ? today
        : today.subtract(const Duration(days: 1));
    if (!loggedDays.contains(cursor)) return 0;

    var streak = 0;
    while (loggedDays.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  @override
  Widget build(BuildContext context) {
    final loggedDays = _loggedDays;
    if (loggedDays == null) return const SizedBox.shrink();
    final colors = context.colors;
    final streak = _currentStreak(loggedDays);
    final active = streak > 0;

    final label = switch (streak) {
      0 => 'no streak yet',
      1 => '1 day streak',
      _ => '$streak day streak',
    };

    final today = _dayKey(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              Icons.local_fire_department_outlined,
              size: 16,
              color: active ? colors.accent : colors.secondaryText,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: active ? colors.accent : colors.secondaryText,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        // Centered, and exactly as wide as the floating bottom bar
        // (BottomSwitcher's own math: two pill widths, the icon gap
        // between them, and the padding/inset each carries — see
        // _barWidth) — rather than left-aligned and stretched across
        // the full page width, which read as disconnected from the one
        // other floating element on this screen.
        Center(
          child: SizedBox(
            width: _barWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var offset = 6; offset >= 0; offset--)
                  _DayDot(
                    day: today.subtract(Duration(days: offset)),
                    logged: loggedDays.contains(
                      today.subtract(Duration(days: offset)),
                    ),
                    isToday: offset == 0,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// BottomSwitcher's own total width, recomputed from its constants
  /// rather than hardcoded: two `_Base` shells (the 3-icon pill, then
  /// the "+" circle) each wrapping a `selectedSize`-square `_SwitcherItem`
  /// with `_itemGap` padding and `_tintInset` padding around that, plus
  /// the `_iconSpacing` gap between icons and between the two shells.
  /// Pill: 3×54 + 2×16 (inter-icon gaps) + 2×4 (item padding) + 2×4
  /// (tint padding) = 210. Circle: 54 + 2×4 + 2×4 = 70. Plus the
  /// 16px gap between them: 210 + 16 + 70 = 296.
  static const _barWidth = 296.0;
}

/// One day in [ReadingStreak]'s week row: a small dot (filled once
/// something was logged that day, outlined otherwise) with its weekday
/// initial underneath, and a ring around today's regardless of whether
/// it's logged yet — so "today" is always findable at a glance even on
/// a day nothing has happened on.
class _DayDot extends StatelessWidget {
  const _DayDot({
    required this.day,
    required this.logged,
    required this.isToday,
  });

  final DateTime day;
  final bool logged;
  final bool isToday;

  static const _weekdayInitials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _size = 20.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      children: [
        Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: logged ? colors.accent : Colors.transparent,
            border: Border.all(
              color: isToday
                  ? colors.accent
                  : (logged ? colors.accent : colors.divider),
              width: isToday ? 2 : 1,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _weekdayInitials[day.weekday - 1],
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: colors.secondaryText,
          ),
        ),
      ],
    );
  }
}
