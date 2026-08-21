import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../library/domain/reading_event.dart';
import '../../../library/presentation/library_scope.dart';
import '../controllers/streaks_controller.dart';
import '../widgets/day_detail_sheet.dart';
import '../widgets/month_dot_grid.dart';

/// The year, broken into months, each a grid of day-dots — a structured
/// take on the inspiration's single 365-dot grid, for reading streaks.
/// Tapping a day opens a smaller sheet for that date. Each dot's shape
/// reflects the strongest shelf command logged that day — see
/// [StreaksController] and `DaySymbol`.
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

  /// Loads the year once, then subscribes to [LibraryController]'s own
  /// event stream so a fresh shelf command updates the grid directly
  /// ([StreaksController.applyEvent]) instead of re-fetching the whole
  /// year from Supabase on every command.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;

    final library = LibraryScope.of(context);
    final controller = _controller = StreaksController(events: library.events);
    controller.load(DateTime.now().year);
    _eventSubscription = library.loggedEvents.listen(controller.applyEvent);
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  /// Shared by every month block — the gap above its dot row (from the
  /// label) and the gap below it (to the next month's label) match.
  /// Kept small on purpose: with all twelve months on screen at once
  /// (see [build] — no scrolling), this is what actually has room to
  /// give.
  static const _rowGap = 6.0;

  /// Small trailing margin below December, on top of [_barFootprint] —
  /// so the last row of dots doesn't sit flush against the floating bar.
  static const _edgeGap = 6.0;

  /// The floating bottom bar's total footprint (bar height + its own
  /// gap + the name label + its margin from the screen edge) — see
  /// bottom_switcher.dart's _outerHeight (70) and root_shell.dart.
  static const _barFootprint = 108.0;

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    final colors = context.colors;
    final controller = _controller;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          // Same top/left inset as the library and profile pages' own
          // headers, so all three sit at the exact same position.
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            0,
          ),
          // The whole year is meant to fit on one screen — every month's
          // own gaps (see [_rowGap]) are kept tight so all twelve, plus
          // the header, stay above the floating bar. "Meant to" is doing
          // real work there: at the largest accessibility text sizes the
          // twelve month labels alone are taller than a phone, and a
          // fixed layout would simply clip December. So it scrolls when
          // it has to and not one pixel before — `physics` refuses the
          // rubber-band bounce that would otherwise make a page that
          // exactly fits feel loose.
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: _edgeGap + _barFootprint),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Same large section-label style as the library page's
                // own "library" header — jetBrainsMono, not a one-off.
                Text(
                  'streak',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
                // Same gap as library's own "library" header down to
                // its first section label ("reading") — that gap is
                // _Header's own md bottom padding *plus* _SectionLabel's
                // own sm bottom padding stacked on top of it, so lg
                // (24) is the true total, not md alone.
                const SizedBox(height: AppSpacing.lg),
                if (controller != null)
                  AnimatedBuilder(
                    animation: controller,
                    builder: (context, _) {
                      // A failed load takes the place of the grid rather
                      // than sitting above it: with nothing loaded the
                      // grid is twelve rows of empty days, which reads
                      // as "you have never logged anything" — the exact
                      // wrong thing to show when the truth is that we
                      // could not find out.
                      final error = controller.errorMessage;
                      if (error != null) {
                        return _LoadFailure(
                          message: error,
                          onRetry: () => controller.load(year),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 1; i <= 12; i++) ...[
                            if (i > 1) const SizedBox(height: _rowGap),
                            MonthDotGrid(
                              month: i,
                              year: year,
                              labelGap: _rowGap,
                              symbolFor: controller.symbolFor,
                              onDayTap: (date) => showDayDetailSheet(
                                context,
                                date,
                                events: controller.eventsFor(date),
                              ),
                            ),
                          ],
                        ],
                      );
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

/// What the streaks page shows instead of the year when it could not be
/// loaded: what went wrong, and the one thing worth offering — another
/// attempt.
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
