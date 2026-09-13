import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../goals/presentation/goal_scope.dart';
import '../../../goals/presentation/widgets/goal_progress_view.dart';
import '../../../goals/presentation/widgets/goal_sheet.dart';
import '../../../library/domain/reading_event.dart';
import '../../../library/presentation/library_scope.dart';
import '../../../shell/presentation/widgets/top_bar.dart';
import '../../domain/reading_stats.dart';
import '../../domain/streak_math.dart';
import '../controllers/streaks_controller.dart';

/// Gap between one day's entries and the next day's label.
const _daySpacing = AppSpacing.lg;

/// Gap between one entry and the next inside the same day.
const _entrySpacing = AppSpacing.sm;

/// How many genres get their own row before the rest fold into "other".
const _topGenres = 5;

/// The stats tab: the yearly reading goal first, then numbers about the
/// shelf (books and pages read, streaks, genres), then the reading journal
/// — every command read back as the line it was typed as, grouped under the
/// day it happened, newest day first.
///
/// Everything here is free. The shelf numbers come straight from
/// [ReadingStats] over the books `LibraryController` already holds, so they
/// update the moment a command lands; only the journal and streaks need
/// the year of `reading_events` [StreaksController] loads.
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  /// Built lazily in [didChangeDependencies], not [initState] — it needs
  /// [LibraryScope.of], which isn't safe to call until this widget is in
  /// the tree.
  StreaksController? _controller;

  StreamSubscription<ReadingEvent>? _eventSubscription;
  StreamSubscription<String>? _clearedSubscription;
  StreamSubscription<void>? _resetSubscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;

    final library = LibraryScope.of(context);
    final controller = _controller = StreaksController(events: library.events);
    controller.load(DateTime.now().year);
    _eventSubscription = library.loggedEvents.listen(controller.applyEvent);
    _clearedSubscription = library.clearedTitles.listen(controller.removeTitle);
    _resetSubscription = library.resets.listen(
      (_) => unawaited(controller.reload(DateTime.now().year)),
    );
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _clearedSubscription?.cancel();
    _resetSubscription?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  /// The floating bottom bar's total footprint — see bottom_switcher.dart.
  static const _barFootprint = 108.0;

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    final controller = _controller;
    final stats = ReadingStats.from(LibraryScope.of(context).books);
    final goals = GoalScope.of(context);
    final goalError = goals.errorMessage;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            0,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: _barFootprint),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TopBar(title: 'stats'),
                const SizedBox(height: AppSpacing.lg),
                if (goals.isLoaded)
                  GoalProgressView(
                    progress: stats.goalProgress(goals.goal),
                    onEdit: () => showGoalSheet(context),
                  )
                else if (goalError != null)
                  _LoadFailure(message: goalError, onRetry: goals.load),
                const SizedBox(height: AppSpacing.xl),
                _StatGrid(stats: stats, streaks: controller),
                if (stats.genres.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xl),
                  const _Heading('genres'),
                  const SizedBox(height: AppSpacing.md),
                  _Genres(genres: stats.genres),
                ],
                const SizedBox(height: AppSpacing.xl),
                const _Heading('journal'),
                const SizedBox(height: AppSpacing.md),
                if (controller != null)
                  AnimatedBuilder(
                    animation: controller,
                    builder: (context, _) {
                      final error = controller.errorMessage;
                      if (error != null) {
                        return _LoadFailure(
                          message: error,
                          onRetry: () => controller.load(year),
                        );
                      }
                      return _Journal(controller: controller);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        text,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: context.colors.secondaryText,
        ),
      ),
    );
  }
}

/// Two columns of numbers. The streak tile waits on the journal's year of
/// events; everything else comes from the shelf and is there immediately.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats, required this.streaks});

  final ReadingStats stats;
  final StreaksController? streaks;

  /// "12,480" — thousands separated, since page counts get long.
  static String count(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  Widget _grid(int? current, int? longest) {
    final rating = stats.averageRating;
    final tiles = [
      _Tile(
        label: 'books read',
        value: count(stats.booksThisYear),
        detail: 'in ${stats.year} · ${count(stats.booksAllTime)} all time',
      ),
      _Tile(
        label: 'pages read',
        value: count(stats.pagesThisYear),
        detail: 'in ${stats.year} · ${count(stats.pagesAllTime)} all time',
      ),
      _Tile(
        label: 'current streak',
        value: current == null ? '—' : count(current),
        detail: longest == null
            ? 'days'
            : '${current == 1 ? 'day' : 'days'} · best $longest this year',
      ),
      _Tile(
        label: 'reading now',
        value: count(stats.reading),
        detail:
            '${count(stats.toRead)} to read · '
            '${count(stats.didNotFinish)} did not finish',
      ),
      if (rating != null)
        _Tile(
          label: 'average rating',
          value: rating.toStringAsFixed(1),
          detail: 'stars, finished books',
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - AppSpacing.md) / 2;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final streaks = this.streaks;
    if (streaks == null) return _grid(null, null);
    return AnimatedBuilder(
      animation: streaks,
      builder: (context, _) {
        if (streaks.isLoading || streaks.errorMessage != null) {
          return _grid(null, null);
        }
        final days = streaks.loggedDays;
        return _grid(StreakMath.current(days), StreakMath.longest(days));
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.detail});

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: '$label: $value, $detail',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 112),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: colors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                height: 1.3,
                color: colors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The top genres as labelled bars scaled to the most common one, with the
/// long tail folded into "other".
class _Genres extends StatelessWidget {
  const _Genres({required this.genres});

  final List<GenreCount> genres;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rest = genres.skip(_topGenres).fold(0, (sum, g) => sum + g.books);
    final rows = <GenreCount>[
      ...genres.take(_topGenres),
      if (rest > 0) (genre: 'other', books: rest),
    ];
    final most = rows.fold(1, (best, g) => g.books > best ? g.books : best);

    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Semantics(
              label:
                  '${row.genre}: ${row.books} '
                  '${row.books == 1 ? 'book' : 'books'}',
              excludeSemantics: true,
              child: Row(
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(
                      row.genre,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 13,
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: row.books / most,
                        child: Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: colors.accent.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '${row.books}',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 13,
                        color: colors.secondaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The list itself: one date label per day with something logged,
/// newest first, each followed by its entries in the order they
/// actually happened.
class _Journal extends StatelessWidget {
  const _Journal({required this.controller});

  final StreaksController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Built up front, not left to `_DayEntries` to discover, because a
    // day whose only command was `delete` renders nothing — and that
    // has to count as "nothing logged" too, not a blank gap followed by
    // silence.
    final days = [
      for (final day in controller.days)
        if (_DayEntries.linesFor(controller.eventsFor(day)) case final lines
            when lines.isNotEmpty)
          (date: day, lines: lines),
    ];

    if (days.isEmpty) {
      return Text(
        controller.isLoading ? '' : 'nothing logged yet — start a book.',
        style: GoogleFonts.jetBrainsMono(
          fontSize: 14,
          color: colors.secondaryText,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, day) in days.indexed) ...[
          if (i > 0) const SizedBox(height: _daySpacing),
          _DayEntries(date: day.date, lines: day.lines),
        ],
      ],
    );
  }
}

/// One day's date label, then every already-resolved [lines] entry —
/// see [linesFor], which decides what's worth journaling.
class _DayEntries extends StatelessWidget {
  const _DayEntries({required this.date, required this.lines});

  final DateTime date;
  final List<String> lines;

  /// The journal lines [events] produce, in order — skipping `delete`,
  /// which isn't a moment worth journaling. Never empty for a day
  /// that's actually worth rendering; `_Journal` uses that to decide
  /// which days to keep.
  static List<String> linesFor(List<ReadingEvent> events) => [
    for (final event in events) ?_lineFor(event),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _dateLabel(date),
          style: GoogleFonts.jetBrainsMono(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colors.secondaryText,
          ),
        ),
        const SizedBox(height: _entrySpacing),
        for (final (i, line) in lines.indexed) ...[
          if (i > 0) const SizedBox(height: _entrySpacing),
          // Same face and size `CommandInput`/`InstructionRow` use on
          // the "+" tab — a logged day is meant to read exactly like
          // the command that produced it.
          Text(
            line,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 16,
              height: 1.5,
              color: colors.primaryText,
            ),
          ),
        ],
      ],
    );
  }

  /// `m.d.yy`, no leading zeros — a plain, diary-style date rather than
  /// a spelled-out one.
  static String _dateLabel(DateTime date) {
    final year = (date.year % 100).toString().padLeft(2, '0');
    return '${date.month}.${date.day}.$year';
  }

  /// The journal line one [event] earns, or null for a type (`delete`)
  /// that isn't part of the story. Reads back almost verbatim what was
  /// typed on the "+" tab, using [ReadingEvent.value] for the number a
  /// command carried — the page an `update` reached, or the rating a
  /// `rate` gave.
  static String? _lineFor(ReadingEvent event) {
    final title = event.title ?? 'a book';
    switch (event.type) {
      case ReadingEventType.start:
        return 'started $title';
      case ReadingEventType.update:
        final page = event.value;
        return page == null
            ? 'read $title'
            : 'read up to page ${page.toInt()} in $title';
      case ReadingEventType.finish:
        return 'finished $title';
      case ReadingEventType.rate:
        final rating = event.value;
        return rating == null
            ? 'rated $title'
            : 'rated $title ${_formatStars(rating)} ${_starWord(rating)}';
      case ReadingEventType.delete:
        return null;
      case ReadingEventType.addToBeRead:
        return 'added $title to read';
      case ReadingEventType.dnf:
        return 'did not finish $title';
    }
  }

  /// Drops a trailing ".0" ("5" rather than "5.0") but keeps a real half
  /// ("4.5") — mirrors `LibraryController._formatStars`.
  static String _formatStars(double rating) {
    return rating == rating.roundToDouble()
        ? rating.toInt().toString()
        : rating.toStringAsFixed(1);
  }

  static String _starWord(double rating) => rating == 1 ? 'star' : 'stars';
}

/// What the stats page shows instead of a section when it could not
/// be loaded: what went wrong, and the one thing worth offering —
/// another attempt.
class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: GoogleFonts.inter(
            fontSize: 14,
            height: 1.5,
            color: colors.secondaryText,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        GestureDetector(
          onTap: onRetry,
          behavior: HitTestBehavior.opaque,
          child: Text(
            'try again',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.accent,
            ),
          ),
        ),
      ],
    );
  }
}
