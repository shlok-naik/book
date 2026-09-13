import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../library/domain/reading_event.dart';
import '../../../library/presentation/library_scope.dart';
import '../../../shell/presentation/widgets/top_bar.dart';
import '../controllers/streaks_controller.dart';

/// Gap between one day's entries and the next day's label.
const _daySpacing = AppSpacing.lg;

/// Gap between one entry and the next inside the same day.
const _entrySpacing = AppSpacing.sm;

/// The reader's own reading history, told back to them as a journal
/// rather than a grid of dots — every command reads exactly like it did
/// when it was typed on the "+" tab (same face, same size), grouped
/// under the day it happened, newest day first.
///
/// A dot grid answers "did I show up today"; this answers "what have I
/// actually been reading" — the warmer of the two questions, and the
/// one worth a whole tab.
class StreaksPage extends StatefulWidget {
  const StreaksPage({super.key});

  @override
  State<StreaksPage> createState() => _StreaksPageState();
}

class _StreaksPageState extends State<StreaksPage> {
  /// Built lazily in [didChangeDependencies], not [initState] — it needs
  /// [LibraryScope.of], which isn't safe to call until this widget is in
  /// the tree. Guards the one-time setup below so it runs exactly once
  /// per page, no matter how many times dependencies change afterwards.
  StreaksController? _controller;

  StreamSubscription<ReadingEvent>? _eventSubscription;
  StreamSubscription<String>? _clearedSubscription;

  /// Loads the year once, then subscribes to [LibraryController]'s own
  /// streams so a fresh shelf command joins the journal directly
  /// ([StreaksController.applyEvent]) and a deleted book's old lines
  /// disappear from it ([StreaksController.removeTitle]), instead of
  /// re-fetching the whole year from Supabase on every command.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;

    final library = LibraryScope.of(context);
    final controller = _controller = StreaksController(events: library.events);
    controller.load(DateTime.now().year);
    _eventSubscription = library.loggedEvents.listen(controller.applyEvent);
    _clearedSubscription = library.clearedTitles.listen(controller.removeTitle);
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _clearedSubscription?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  /// The floating bottom bar's total footprint (bar height + its own
  /// gap + the name label + its margin from the screen edge) — see
  /// bottom_switcher.dart's _outerHeight (70) and root_shell.dart.
  static const _barFootprint = 108.0;

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    final controller = _controller;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          // Same top/left inset as the library and log pages' own
          // headers, so all three sit at the exact same position.
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
                // The shared header every top-level page wears — the
                // settings gear, then the page's own name in the same
                // jetBrainsMono style all four have always used.
                const TopBar(title: 'streak'),
                const SizedBox(height: AppSpacing.lg),
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

/// What the streaks page shows instead of the journal when it could not
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
