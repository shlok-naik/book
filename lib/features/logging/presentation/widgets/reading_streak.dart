import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../goals/domain/daily_goal.dart';
import '../../../goals/presentation/daily_goal_controller.dart';
import '../../../goals/presentation/widgets/daily_goal_prompt.dart';
import '../../../library/domain/reading_event.dart';
import '../../../library/presentation/library_scope.dart';
import '../../../streaks/domain/streak_math.dart';

/// The full streak readout on the add tab: a "N day streak" heading
/// over a row of the last seven days, each marked for whether anything
/// was logged — the same shape as Fable's own streak card, restyled to
/// this app's own quiet, lowercase, dot-not-emoji language, and with no
/// card chrome of its own — the streak/memory pages next door are both
/// plain journals, not boxed cards, so this sits directly on the page
/// background the same way.
///
/// Read-only itself: a day counts either because a command was logged
/// against a real book that day (`start`/`update <page>`/`finish`/`rate`
/// — every `reading_events` row is tied to one) **or** because the reader
/// ticked [DailyGoalPrompt] directly above, which is the one "I read
/// today" the app does have. The two sets are unioned here so the run is
/// counted in one place; the prompt says nothing about streaks itself.
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
  StreamSubscription<ReadingEvent>? _events;
  StreamSubscription<void>? _resets;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    final library = LibraryScope.read(context);
    // A command logged from this very page lights today's dot without a
    // refetch; a replaced library (an import, a linked account) reloads.
    _events = library.loggedEvents.listen(_onEvent);
    _resets = library.resets.listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  @override
  void dispose() {
    _events?.cancel();
    _resets?.cancel();
    super.dispose();
  }

  void _onEvent(ReadingEvent event) {
    final days = _loggedDays;
    if (days == null || event.type == ReadingEventType.delete) return;
    final day = _dayKey(event.occurredAt.toLocal());
    if (days.contains(day)) return;
    setState(() => _loggedDays = {...days, day});
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

  static DateTime _dayKey(DateTime date) => StreakMath.dayKey(date);

  static int _currentStreak(Set<DateTime> loggedDays) =>
      StreakMath.current(loggedDays);

  @override
  Widget build(BuildContext context) {
    final loggedDays = _loggedDays;
    if (loggedDays == null) return const SizedBox.shrink();
    return ValueListenableBuilder<DailyGoal>(
      valueListenable: DailyGoalController.goal,
      builder: (context, goal, _) =>
          _readout(context, {...loggedDays, ...goal.markedDays}),
    );
  }

  Widget _readout(BuildContext context, Set<DateTime> loggedDays) {
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
              style: context.fonts.interface(
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
          style: context.fonts.interface(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: colors.secondaryText,
          ),
        ),
      ],
    );
  }
}
