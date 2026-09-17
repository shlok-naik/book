import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/formatting/numbers.dart';
import '../../../../core/purchases/purchases_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../goals/domain/reading_goal.dart';
import '../../../goals/presentation/goal_scope.dart';
import '../../../goals/presentation/widgets/goal_progress_view.dart';
import '../../../library/domain/book_note.dart';
import '../../../library/domain/library_exception.dart';
import '../../../library/domain/reading_event.dart';
import '../../../library/presentation/library_scope.dart';
import '../../../paywall/presentation/pages/paywall_page.dart';
import '../../../paywall/presentation/pro_gate.dart';
import '../../../shell/presentation/widgets/bottom_switcher.dart';
import '../../../shell/presentation/widgets/top_bar.dart';
import '../../domain/reading_heatmap.dart';
import '../../domain/reading_stats.dart';
import '../controllers/streaks_controller.dart';
import 'year_in_books_page.dart';

/// How many genres get their own row before the rest fold into "other".
const _topGenres = 5;

/// Shared by every monthly chart on this page, so "J" and "Jan" always mean
/// the same column no matter which chart is drawing it.
const _monthInitials = [
  'J',
  'F',
  'M',
  'A',
  'M',
  'J',
  'J',
  'A',
  'S',
  'O',
  'N',
  'D',
];
const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _monthName(int index) => _monthNames[index];

/// The stats tab: the yearly reading goal first (read-only here — a goal is
/// only ever changed from settings), then the basic tier free readers keep
/// — books/pages read, the reading-days heatmap and how the shelf breaks
/// down — then the deeper insights cactus pro unlocks: three charts (books
/// finished per month, pages read per month, pace toward the goal), genres
/// and tags. There is no journal any more; a book's own start and finish
/// dates live on its book page instead.
///
/// The shelf numbers come straight from [ReadingStats] over the books
/// `LibraryController` already holds (and its import date, the baseline an
/// imported library's stats count from), so they update the moment a
/// command lands; the heatmap additionally needs the year of
/// `reading_events` [StreaksController] loads. A free reader sees a faded,
/// inert preview where the charts, genres and tags would be (see
/// [_LockedInsights]) — the same discoverability-without-access treatment
/// settings gives "themes and icons".
class StatsPage extends StatefulWidget {
  const StatsPage({super.key, this.purchases});

  /// Injection point for tests: a fake wrapping fake customer info
  /// instead of the real RevenueCat SDK. Null in the app.
  final PurchasesService? purchases;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> with ProGateState<StatsPage> {
  @override
  PurchasesService? get purchasesOverride => widget.purchases;

  @override
  PaywallFeature get paywallFeature => PaywallFeature.expression;

  /// Built lazily in [didChangeDependencies], not [initState] — it needs
  /// [LibraryScope.of], which isn't safe to call until this widget is in
  /// the tree.
  StreaksController? _controller;

  StreamSubscription<ReadingEvent>? _eventSubscription;
  StreamSubscription<String>? _clearedSubscription;
  StreamSubscription<void>? _resetSubscription;
  StreamSubscription<void>? _tagsSubscription;

  /// Every `book_tags` row, for the pro "tags" section — null until the
  /// first fetch lands. Fetched only once the page is unlocked (a free
  /// reader's preview uses invented rows, see [_LockedInsights]) and
  /// refetched whenever [LibraryController.tagsChanged] or a library
  /// reset says it went stale; counted against the live shelf in [build].
  List<BookTag>? _allTags;
  bool _tagsLoading = false;
  String? _tagsError;

  /// Fetches [_allTags]. Deliberately writes [_tagsLoading] without
  /// `setState` before the first await, so [build] may call it — nothing
  /// visible changes until the fetch resolves.
  Future<void> _loadTags() async {
    if (_tagsLoading) return;
    _tagsLoading = true;
    try {
      final tags = await LibraryScope.read(context).notes.fetchAllTags();
      if (!mounted) return;
      setState(() {
        _allTags = tags;
        _tagsError = null;
      });
    } on LibraryException catch (error) {
      if (!mounted) return;
      setState(() => _tagsError = error.message);
    } on Object catch (error, stackTrace) {
      // Anything else must still land as an error: left with neither tags
      // nor an error, [build] would start this fetch again on every rebuild.
      AppLogger.error(
        'StatsPage',
        'Loading tags failed unexpectedly.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() => _tagsError = "Couldn't load your tags.");
    } finally {
      _tagsLoading = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;

    final library = LibraryScope.of(context);
    final controller = _controller = StreaksController(events: library.events);
    controller.load(DateTime.now().year);
    _eventSubscription = library.loggedEvents.listen(controller.applyEvent);
    _clearedSubscription = library.clearedTitles.listen(controller.removeTitle);
    _resetSubscription = library.resets.listen((_) {
      unawaited(controller.reload(DateTime.now().year));
      if (_allTags != null) unawaited(_loadTags());
    });
    _tagsSubscription = library.tagsChanged.listen((_) {
      if (_allTags != null || _tagsError != null) unawaited(_loadTags());
    });
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _clearedSubscription?.cancel();
    _resetSubscription?.cancel();
    _tagsSubscription?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  /// The floating bottom bar's footprint — see [BottomSwitcher.pageFootprint].
  static const _barFootprint = BottomSwitcher.pageFootprint;

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    final controller = _controller;
    final library = LibraryScope.of(context);
    final stats = ReadingStats.forShelf(
      library.books,
      importedAt: library.importedAt,
    );
    final goals = GoalScope.of(context);
    final goalError = goals.errorMessage;
    if (isProUnlocked && _allTags == null && _tagsError == null) {
      unawaited(_loadTags());
    }
    final allTags = _allTags;
    final tagError = _tagsError;

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
                    editable: false,
                    progress: stats.goalProgress(goals.goal),
                  )
                else if (goalError != null)
                  _LoadFailure(message: goalError, onRetry: goals.load),
                const SizedBox(height: AppSpacing.xl),
                _StatGrid(stats: stats),
                const SizedBox(height: AppSpacing.lg),
                _YearCardEntry(
                  locked: !isProUnlocked,
                  busy: unlockBusy,
                  onTap: isProUnlocked
                      ? () => unawaited(
                          openYearInBooks(context, purchases: widget.purchases),
                        )
                      : unlockPro,
                ),
                const SizedBox(height: AppSpacing.xl),
                // Free on every plan: reading days are the same thing the
                // add tab's streak already shows, just a whole year of it.
                const _Heading('reading days'),
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
                      // Nothing until the year has loaded: an empty grid
                      // would read as "you haven't read at all" for a beat.
                      if (controller.isLoading) {
                        return const SizedBox.shrink();
                      }
                      return _ReadingHeatmapView(
                        heatmap: ReadingHeatmap.fromCounts(
                          year,
                          controller.activityByDay,
                          today: DateTime.now(),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: AppSpacing.xl),
                const _Heading('your shelf'),
                const SizedBox(height: AppSpacing.md),
                _ShelfDonut(stats: stats),
                const SizedBox(height: AppSpacing.xl),
                if (isProUnlocked) ...[
                  const _Heading('books per month'),
                  const SizedBox(height: AppSpacing.md),
                  _ActivityChart(stats: stats),
                  const SizedBox(height: AppSpacing.xl),
                  const _Heading('pages per month'),
                  const SizedBox(height: AppSpacing.md),
                  _PagesChart(stats: stats),
                  const SizedBox(height: AppSpacing.xl),
                  const _Heading('pace'),
                  const SizedBox(height: AppSpacing.md),
                  _PaceChart(
                    stats: stats,
                    goal: stats.goalProgress(goals.goal),
                  ),
                  if (stats.genres.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xl),
                    const _Heading('genres'),
                    const SizedBox(height: AppSpacing.md),
                    _CountBars.genres(stats.genres),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  const _Heading('tags'),
                  const SizedBox(height: AppSpacing.md),
                  if (tagError != null && allTags == null)
                    _LoadFailure(message: tagError, onRetry: _loadTags)
                  else if (allTags != null)
                    _TagCounts(
                      counts: ReadingStats.tagCounts(allTags, library.books),
                    ),
                ] else
                  _LockedInsights(
                    stats: stats,
                    goal: stats.goalProgress(goals.goal),
                    busy: unlockBusy,
                    onTap: unlockPro,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The way into "your year in books" — a shareable card of the year.
/// Shown to every reader; a free reader's tap opens the paywall instead.
class _YearCardEntry extends StatelessWidget {
  const _YearCardEntry({
    required this.locked,
    required this.busy,
    required this.onTap,
  });

  final bool locked;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: locked
          ? 'Your year in books, a shareable card. Cactus pro.'
          : 'Your year in books, a shareable card.',
      excludeSemantics: true,
      onTap: busy
          ? null
          : () {
              AppHaptics.selection();
              onTap();
            },
      child: InkWell(
        key: const ValueKey('year-card-entry'),
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: busy
            ? null
            : () {
                AppHaptics.selection();
                onTap();
              },
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: colors.divider),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_outlined, color: colors.accent),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'your year in books',
                      style: context.fonts.interface(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.primaryText,
                      ),
                    ),
                    Text(
                      'a card to share',
                      style: context.fonts.body(
                        fontSize: 13,
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                locked ? Icons.lock_outline : Icons.chevron_right,
                size: 20,
                color: colors.secondaryText,
              ),
            ],
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
        style: context.fonts.interface(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: context.colors.secondaryText,
        ),
      ),
    );
  }
}

/// Two columns of numbers, straight from the shelf.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats});

  final ReadingStats stats;

  static String count(int value) => formatThousands(value);

  @override
  Widget build(BuildContext context) {
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
              style: context.fonts.interface(
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
                style: context.fonts.interface(
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
              style: context.fonts.interface(
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

/// Books finished per month this year, as a bar chart — the one graph on
/// the page that reads at a glance whether reading has picked up or
/// tapered off, rather than the single "books this year" number the grid
/// above already gives.
class _ActivityChart extends StatelessWidget {
  const _ActivityChart({required this.stats});

  final ReadingStats stats;

  static const _chartHeight = 120.0;
  static const _barWidth = 16.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final months = stats.booksByMonth;
    final most = months.fold(0, (best, count) => count > best ? count : best);
    final currentMonth = DateTime.now().month - 1;

    if (most == 0) {
      return Text(
        'nothing finished in ${stats.year} yet.',
        style: context.fonts.interface(
          fontSize: 13,
          color: colors.secondaryText,
        ),
      );
    }

    return Semantics(
      label:
          'Books finished per month in ${stats.year}: '
          '${[for (var i = 0; i < 12; i++) '${_monthName(i)} ${months[i]}'].join(', ')}.',
      excludeSemantics: true,
      child: SizedBox(
        height: _chartHeight + 28,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 12; i++)
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: _chartHeight,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Tooltip(
                          message: '${_monthName(i)}: ${months[i]}',
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: _barWidth,
                            height: months[i] == 0
                                ? 2
                                : _chartHeight * (months[i] / most),
                            decoration: BoxDecoration(
                              color: i == currentMonth
                                  ? colors.accent
                                  : colors.accent.withValues(
                                      alpha: months[i] == 0 ? 0.15 : 0.55,
                                    ),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _monthInitials[i],
                      style: context.fonts.interface(
                        fontSize: 11,
                        fontWeight: i == currentMonth
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: i == currentMonth
                            ? colors.accent
                            : colors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pages read per month this year, as a filled line chart — the same shape
/// [_ActivityChart] draws in bars, but pages swing more than book counts do
/// (one 900-page month can hide three thin ones), so a line reads that
/// better than bars would.
class _PagesChart extends StatelessWidget {
  const _PagesChart({required this.stats});

  final ReadingStats stats;

  static const _chartHeight = 120.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final months = stats.pagesByMonth;
    final most = months.fold(0, (best, count) => count > best ? count : best);

    if (most == 0) {
      return Text(
        'no pages logged in ${stats.year} yet.',
        style: context.fonts.interface(
          fontSize: 13,
          color: colors.secondaryText,
        ),
      );
    }

    return Semantics(
      label:
          'Pages read per month in ${stats.year}: '
          '${[for (var i = 0; i < 12; i++) '${_monthName(i)} ${months[i]}'].join(', ')}.',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: _chartHeight,
            width: double.infinity,
            child: CustomPaint(
              painter: _LineChartPainter(
                series: [
                  _LineSeries(
                    values: [for (final count in months) count.toDouble()],
                    color: colors.accent,
                    filled: true,
                  ),
                ],
                maxY: most.toDouble(),
              ),
            ),
          ),
          const SizedBox(height: 6),
          _MonthLabels(currentMonth: DateTime.now().month - 1),
        ],
      ),
    );
  }
}

/// The row of month initials under every chart on this page, with the
/// current one picked out — shared so the columns line up identically no
/// matter which chart sits above them.
class _MonthLabels extends StatelessWidget {
  const _MonthLabels({required this.currentMonth});

  final int currentMonth;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        for (var i = 0; i < 12; i++)
          Expanded(
            child: Text(
              _monthInitials[i],
              textAlign: TextAlign.center,
              style: context.fonts.interface(
                fontSize: 11,
                fontWeight: i == currentMonth
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: i == currentMonth ? colors.accent : colors.secondaryText,
              ),
            ),
          ),
      ],
    );
  }
}

/// One value per month, some of which may be entirely absent (a series that
/// stops partway through the year, like [_PaceChart]'s actual-progress
/// line once it reaches the current month).
class _LineSeries {
  const _LineSeries({
    required this.values,
    required this.color,
    this.xs,
    this.dashed = false,
    this.filled = false,
    this.strokeWidth = 2.5,
    this.dots = true,
  });

  final List<double?> values;

  /// Where each value sits across the chart, 0..1 — for a series plotted at
  /// real dates (the pace chart after an import) rather than one point per
  /// month. Null spaces [values] evenly, as every monthly series does. Same
  /// length as [values] when given.
  final List<double>? xs;

  /// Whether a solid line marks each point with a dot.
  final bool dots;
  final Color color;
  final bool dashed;
  final bool filled;
  final double strokeWidth;
}

/// Draws one or more [_LineSeries] against a shared 0..[maxY] scale, evenly
/// spaced across the width. A null value breaks the line rather than
/// drawing a point for it, so a series that hasn't reached December yet
/// just stops instead of dropping to zero.
class _LineChartPainter extends CustomPainter {
  _LineChartPainter({required this.series, required this.maxY});

  final List<_LineSeries> series;
  final double maxY;

  static const _dashLength = 5.0;
  static const _dashGap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (maxY <= 0 || size.width <= 0 || size.height <= 0) return;

    for (final line in series) {
      final points = <Offset?>[
        for (var i = 0; i < line.values.length; i++)
          if (line.values[i] case final value?)
            Offset(switch (line.xs) {
              final xs? => size.width * xs[i].clamp(0.0, 1.0),
              _ =>
                line.values.length == 1
                    ? 0
                    : size.width * i / (line.values.length - 1),
            }, size.height * (1 - (value / maxY).clamp(0.0, 1.0)))
          else
            null,
      ];

      if (line.filled) _paintFill(canvas, size, points, line.color);

      final paint = Paint()
        ..color = line.color
        ..strokeWidth = line.strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      Offset? previous;
      for (final point in points) {
        if (previous != null && point != null) {
          if (line.dashed) {
            _paintDashedSegment(canvas, previous, point, paint);
          } else {
            canvas.drawLine(previous, point, paint);
          }
        }
        previous = point;
      }

      if (!line.dashed && line.dots) {
        final dotPaint = Paint()..color = line.color;
        for (final point in points) {
          if (point != null) {
            canvas.drawCircle(point, line.strokeWidth, dotPaint);
          }
        }
      }
    }
  }

  /// Fills under one unbroken contiguous run of points — the common case
  /// (a whole year of data) draws one region; a line with gaps fills each
  /// run it actually has data for, rather than bridging the gap.
  void _paintFill(Canvas canvas, Size size, List<Offset?> points, Color color) {
    final fillPaint = Paint()..color = color.withValues(alpha: 0.12);
    var run = <Offset>[];
    void flush() {
      if (run.length > 1) {
        final path = Path()..moveTo(run.first.dx, size.height);
        for (final point in run) {
          path.lineTo(point.dx, point.dy);
        }
        path.lineTo(run.last.dx, size.height);
        path.close();
        canvas.drawPath(path, fillPaint);
      }
      run = [];
    }

    for (final point in points) {
      if (point == null) {
        flush();
      } else {
        run.add(point);
      }
    }
    flush();
  }

  void _paintDashedSegment(Canvas canvas, Offset a, Offset b, Paint paint) {
    final total = (b - a).distance;
    if (total == 0) return;
    final direction = (b - a) / total;
    var drawn = 0.0;
    var drawing = true;
    while (drawn < total) {
      final length = drawing ? _dashLength : _dashGap;
      final next = math.min(drawn + length, total);
      if (drawing) {
        canvas.drawLine(a + direction * drawn, a + direction * next, paint);
      }
      drawn = next;
      drawing = !drawing;
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.series != series || oldDelegate.maxY != maxY;
}

/// A small colored swatch for a chart legend — a solid bar for a solid
/// line, three short dashes for a dashed one, so the legend reads as a
/// miniature of the line it's naming.
class _LegendSwatch extends StatelessWidget {
  const _LegendSwatch({required this.color, this.dashed = false});

  final Color color;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    if (!dashed) {
      return Container(
        width: 14,
        height: 3,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      );
    }
    return SizedBox(
      width: 14,
      height: 3,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: 3,
              height: 3,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
        ],
      ),
    );
  }
}

/// Cumulative books finished this year against a steady pace toward the
/// goal — the one chart on the page that answers "am I on track", rather
/// than just "what happened". Without a goal it still shows how the
/// reader's own total has grown, just with nothing to compare it to.
class _PaceChart extends StatelessWidget {
  const _PaceChart({required this.stats, required this.goal});

  final ReadingStats stats;

  /// From `stats.goalProgress(goals.goal)` — null with no goal set.
  final ReadingGoal? goal;

  static const _chartHeight = 120.0;

  @override
  Widget build(BuildContext context) {
    final baseline = stats.paceBaseline;
    if (baseline != null) {
      return _PaceSinceImport(
        stats: stats,
        goal: this.goal,
        baseline: baseline,
      );
    }
    final colors = context.colors;
    final goal = this.goal;
    final currentMonth =
        DateTime.now().month; // 1-12, so index 0..currentMonth-1 has happened.

    var running = 0.0;
    final cumulative = <double>[];
    for (final count in stats.booksByMonth) {
      running += count;
      cumulative.add(running);
    }
    final actual = <double?>[
      for (var i = 0; i < 12; i++) i < currentMonth ? cumulative[i] : null,
    ];

    // Nothing finished this year means there is no line worth drawing — a
    // flat zero under a dashed "steady pace" only reads as a chart of
    // falling behind. Just say so, whether or not a goal is set.
    if (running == 0) {
      return Text(
        'no books read in ${stats.year} yet.',
        style: context.fonts.interface(
          fontSize: 13,
          color: colors.secondaryText,
        ),
      );
    }

    final maxY = goal == null
        ? running
        : math.max(goal.goal.toDouble(), running);
    final ideal = goal == null
        ? null
        : [for (var i = 0; i < 12; i++) goal.goal * (i + 1) / 12];

    return Semantics(
      label: goal == null
          ? "You've finished ${running.toInt()} "
                '${running == 1 ? 'book' : 'books'} so far in ${stats.year}.'
          : 'Reading pace toward your goal of ${goal.goal} books: '
                '${running.toInt()} finished, ${goal.paceLabel(DateTime.now())}.',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (goal != null) ...[
            // A Wrap, not a Row: on a narrow phone or with larger text the
            // legend and the pace label don't fit one line, and a Row ran
            // off the right edge. On one line the label still sits right.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _LegendSwatch(color: colors.accent),
                        const SizedBox(width: 6),
                        Text(
                          'you',
                          style: _legendStyle(
                            context,
                            colors,
                            colors.primaryText,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _LegendSwatch(
                          color: colors.secondaryText,
                          dashed: true,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'steady pace',
                          style: _legendStyle(
                            context,
                            colors,
                            colors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Text(
                  goal.paceLabel(DateTime.now()),
                  style: _legendStyle(context, colors, colors.accent),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          SizedBox(
            height: _chartHeight,
            width: double.infinity,
            child: CustomPaint(
              painter: _LineChartPainter(
                series: [
                  if (ideal != null)
                    _LineSeries(
                      values: ideal,
                      color: colors.secondaryText,
                      dashed: true,
                      strokeWidth: 1.5,
                    ),
                  _LineSeries(
                    values: actual,
                    color: colors.accent,
                    filled: goal == null,
                  ),
                ],
                maxY: maxY <= 0 ? 1 : maxY,
              ),
            ),
          ),
          const SizedBox(height: 6),
          _MonthLabels(currentMonth: currentMonth - 1),
        ],
      ),
    );
  }

  static TextStyle _legendStyle(
    BuildContext context,
    AppColors colors,
    Color color,
  ) => context.fonts.interface(fontSize: 12, color: color);
}

/// [_PaceChart] for a library imported this year. Imported history isn't
/// reading done in cactus, so pace starts at the import instead of January:
///
/// * a thin **baseline** line runs across the chart at the number of books
///   already finished this year when the import happened — above the x axis
///   whenever that's more than zero;
/// * **you** starts on that line at the import date and steps up at each
///   book finished since, at its real date, to today — relative to the
///   baseline, not to the start of a month;
/// * **steady pace** (with a goal) runs from the baseline at the import to
///   the goal at year end, which is also what [ReadingGoal.paceLabel] now
///   measures against.
class _PaceSinceImport extends StatelessWidget {
  const _PaceSinceImport({
    required this.stats,
    required this.goal,
    required this.baseline,
  });

  final ReadingStats stats;
  final ReadingGoal? goal;
  final PaceBaseline baseline;

  static const _chartHeight = 120.0;

  /// [date]'s position across [year], 0 (Jan 1) to 1 (the end of Dec 31).
  static double _fractionOfYear(DateTime date, int year) {
    final local = date.toLocal();
    final start = DateTime(year);
    final end = DateTime(year + 1);
    return (local.difference(start).inMinutes / end.difference(start).inMinutes)
        .clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final goal = this.goal;
    final now = DateTime.now();
    final base = baseline.books.toDouble();
    final since = stats.finishesAfterBaseline;
    final total = base + since.length;

    if (total == 0 && goal == null) {
      return Text(
        'no books read in ${stats.year} yet.',
        style: context.fonts.interface(
          fontSize: 13,
          color: colors.secondaryText,
        ),
      );
    }

    final startX = _fractionOfYear(baseline.at, stats.year);
    final todayX = _fractionOfYear(now, stats.year);
    final xs = <double>[startX];
    final values = <double?>[base];
    for (final (i, finished) in since.indexed) {
      final x = _fractionOfYear(finished, stats.year);
      // A step: level up to the finish, then up by one book at it.
      xs
        ..add(x)
        ..add(x);
      values
        ..add(base + i)
        ..add(base + i + 1);
    }
    if (todayX > xs.last) {
      xs.add(todayX);
      values.add(total);
    }

    final maxY = math.max(goal?.goal.toDouble() ?? 0, total);
    final dateLabel =
        '${baseline.at.toLocal().month}.${baseline.at.toLocal().day}';
    final paceLabel = goal?.paceLabel(now);

    return Semantics(
      label:
          'Reading pace since your import on $dateLabel: '
          '${baseline.books} ${baseline.books == 1 ? 'book' : 'books'} '
          'already read this year, ${since.length} finished since'
          '${goal == null ? '' : ', goal ${goal.goal}, $paceLabel'}.',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _legend(
                context,
                colors,
                colors.accent,
                'you',
                colors.primaryText,
              ),
              if (goal != null)
                _legend(
                  context,
                  colors,
                  colors.secondaryText,
                  'steady pace',
                  colors.secondaryText,
                  dashed: true,
                ),
              _legend(
                context,
                colors,
                colors.divider,
                'imported $dateLabel · ${baseline.books}',
                colors.secondaryText,
              ),
              if (paceLabel != null)
                Text(
                  paceLabel,
                  style: context.fonts.interface(
                    fontSize: 12,
                    color: colors.accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: _chartHeight,
            width: double.infinity,
            child: CustomPaint(
              painter: _LineChartPainter(
                series: [
                  _LineSeries(
                    values: [base, base],
                    xs: const [0, 1],
                    color: colors.divider,
                    strokeWidth: 2,
                    dots: false,
                  ),
                  if (goal != null)
                    _LineSeries(
                      values: [base, goal.goal.toDouble()],
                      xs: [startX, 1],
                      color: colors.secondaryText,
                      dashed: true,
                      strokeWidth: 1.5,
                    ),
                  _LineSeries(
                    values: values,
                    xs: xs,
                    color: colors.accent,
                    dots: false,
                  ),
                ],
                maxY: maxY <= 0 ? 1 : maxY,
              ),
            ),
          ),
          const SizedBox(height: 6),
          _MonthLabels(currentMonth: now.month - 1),
        ],
      ),
    );
  }

  static Widget _legend(
    BuildContext context,
    AppColors colors,
    Color swatch,
    String text,
    Color textColor, {
    bool dashed = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LegendSwatch(color: swatch, dashed: dashed),
        const SizedBox(width: 6),
        Text(
          text,
          style: context.fonts.interface(fontSize: 12, color: textColor),
        ),
      ],
    );
  }
}

/// The current shelf, as a donut: reading, to read, finished, and did not
/// finish, with the total in the middle — the one chart that's a snapshot
/// of right now rather than a trend over the year.
class _ShelfDonut extends StatelessWidget {
  const _ShelfDonut({required this.stats});

  final ReadingStats stats;

  static const _size = 132.0;
  static const _strokeWidth = 18.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final segments = [
      (label: 'reading', count: stats.reading, color: colors.accent),
      (
        label: 'finished',
        count: stats.booksAllTime,
        color: colors.accent.withValues(alpha: 0.45),
      ),
      (
        label: 'to read',
        count: stats.toRead,
        color: colors.secondaryText.withValues(alpha: 0.45),
      ),
      (
        label: 'did not finish',
        count: stats.didNotFinish,
        color: colors.divider,
      ),
    ];
    final total = segments.fold(0, (sum, s) => sum + s.count);

    if (total == 0) {
      return Text(
        'nothing on your shelf yet.',
        style: context.fonts.interface(
          fontSize: 13,
          color: colors.secondaryText,
        ),
      );
    }

    return Semantics(
      label:
          'Your shelf: '
          '${[for (final s in segments)
            if (s.count > 0) '${s.label} ${s.count}'].join(', ')}.',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: _size,
            height: _size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(_size, _size),
                  painter: _DonutPainter(
                    segments: [
                      for (final s in segments)
                        (value: s.count.toDouble(), color: s.color),
                    ],
                    strokeWidth: _strokeWidth,
                    background: colors.divider.withValues(alpha: 0.3),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$total',
                      style: context.fonts.interface(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: colors.primaryText,
                      ),
                    ),
                    Text(
                      total == 1 ? 'book' : 'books',
                      style: context.fonts.interface(
                        fontSize: 11,
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in segments)
                  if (s.count > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: s.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s.label,
                              overflow: TextOverflow.ellipsis,
                              style: context.fonts.interface(
                                fontSize: 13,
                                color: colors.primaryText,
                              ),
                            ),
                          ),
                          Text(
                            '${s.count}',
                            style: context.fonts.interface(
                              fontSize: 13,
                              color: colors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The ring [_ShelfDonut] draws: one arc per segment, in order, starting
/// from the top. A zero-count segment is skipped rather than drawn as a
/// zero-width arc.
class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.segments,
    required this.strokeWidth,
    required this.background,
  });

  final List<({double value, Color color})> segments;
  final double strokeWidth;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold(0.0, (sum, s) => sum + s.value);
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );

    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = background
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
    if (total <= 0) return;

    var start = -math.pi / 2;
    for (final segment in segments) {
      if (segment.value <= 0) continue;
      final sweep = 2 * math.pi * (segment.value / total);
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..color = segment.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.segments != segments ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.background != background;
}

/// The top rows (genres, or tags) as labelled bars scaled to the most
/// common one, with the long tail folded into "other".
class _CountBars extends StatelessWidget {
  const _CountBars({required this.rows});

  _CountBars.genres(List<GenreCount> genres)
    : this(rows: [for (final g in genres) (label: g.genre, books: g.books)]);

  _CountBars.tags(List<TagCount> tags)
    : this(rows: [for (final t in tags) (label: t.tag, books: t.books)]);

  /// Already sorted, most books first.
  final List<({String label, int books})> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final all = this.rows;
    final rest = all.skip(_topGenres).fold(0, (sum, g) => sum + g.books);
    final rows = <({String label, int books})>[
      ...all.take(_topGenres),
      if (rest > 0) (label: 'other', books: rest),
    ];
    final most = rows.fold(1, (best, g) => g.books > best ? g.books : best);

    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Semantics(
              label:
                  '${row.label}: ${row.books} '
                  '${row.books == 1 ? 'book' : 'books'}',
              excludeSemantics: true,
              child: Row(
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(
                      row.label,
                      overflow: TextOverflow.ellipsis,
                      style: context.fonts.interface(
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
                      style: context.fonts.interface(
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

/// What a free reader sees in place of the trend charts and genres: the
/// real [_ActivityChart]/[_PagesChart]/[_PaceChart]/[_Genres], faded and
/// inert — a shape isn't an identifying detail the way a journal line's
/// title/date is, so unlike [_LockedJournal] this previews the reader's
/// own data rather than invented rows — plus a line naming the way out.
/// Same "faded, never hidden" tap-to-unlock treatment as [_LockedJournal]
/// and settings' `_CustomisationSection`.
const _previewTags = <TagCount>[
  (tag: 'favourites', books: 6),
  (tag: 'book club', books: 4),
  (tag: 'cosy', books: 2),
];

class _LockedInsights extends StatelessWidget {
  const _LockedInsights({
    required this.stats,
    required this.goal,
    required this.busy,
    required this.onTap,
  });

  final ReadingStats stats;

  /// From `stats.goalProgress(goals.goal)` — null with no goal set.
  final ReadingGoal? goal;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label:
          'Reading trends, genres and tags, locked. Upgrade to cactus '
          'pro to unlock. Double tap to upgrade.',
      excludeSemantics: true,
      onTap: busy ? null : onTap,
      child: GestureDetector(
        onTap: busy ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Opacity(
              opacity: 0.4,
              child: IgnorePointer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Heading('books per month'),
                    const SizedBox(height: AppSpacing.md),
                    _ActivityChart(stats: stats),
                    const SizedBox(height: AppSpacing.xl),
                    const _Heading('pages per month'),
                    const SizedBox(height: AppSpacing.md),
                    _PagesChart(stats: stats),
                    const SizedBox(height: AppSpacing.xl),
                    const _Heading('pace'),
                    const SizedBox(height: AppSpacing.md),
                    _PaceChart(stats: stats, goal: goal),
                    if (stats.genres.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xl),
                      const _Heading('genres'),
                      const SizedBox(height: AppSpacing.md),
                      _CountBars.genres(stats.genres),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    const _Heading('tags'),
                    const SizedBox(height: AppSpacing.md),
                    // Invented, like [_LockedJournal]'s rows: a tag is
                    // the reader's own words, unlike a chart's shape.
                    const _TagCounts(counts: _previewTags),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'cactus pro unlocks your reading trends, genres and tags — '
              'tap to upgrade',
              style: context.fonts.interface(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "tags" section: how many books carry each of the reader's tags, as
/// the same labelled bars genres use. Without any tag on any book it says
/// how to start rather than drawing an empty chart.
class _TagCounts extends StatelessWidget {
  const _TagCounts({required this.counts});

  final List<TagCount> counts;

  @override
  Widget build(BuildContext context) {
    if (counts.isEmpty) {
      return Text(
        'no tagged books yet — try add tag <tag> <book>.',
        style: context.fonts.interface(
          fontSize: 13,
          color: context.colors.secondaryText,
        ),
      );
    }
    return _CountBars.tags(counts);
  }
}

/// A year of reading days as twelve small month calendars, three to a
/// row — each day a square shaded by how much was logged on it
/// ([ReadingHeatmap.levelFor]). Month blocks rather than one long 53-week
/// strip: at phone width a year-long strip leaves every square a few
/// pixels wide, where a month block keeps them large enough to read and
/// labels each month outright.
///
/// Days still to come are left empty rather than drawn as "nothing
/// logged", and today carries an outline. One semantics node summarises
/// the whole year — reading 365 squares aloud would help nobody.
class _ReadingHeatmapView extends StatelessWidget {
  const _ReadingHeatmapView({required this.heatmap});

  final ReadingHeatmap heatmap;

  static const _monthsPerRow = 3;
  static const _cellGap = 2.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final busiest = heatmap.busiestMonth;
    final days = heatmap.readingDays;
    final summary = days == 0
        ? 'nothing logged in ${heatmap.year} yet.'
        : '$days ${days == 1 ? 'day' : 'days'} read in ${heatmap.year}'
              '${busiest == null ? '' : ' · most in ${_monthName(busiest - 1).toLowerCase()}'}';

    return Semantics(
      label: days == 0
          ? 'Reading days: nothing logged in ${heatmap.year} yet.'
          : 'Reading days: $days in ${heatmap.year}'
                '${busiest == null ? '' : ', most in ${_monthNames[busiest - 1]}'}.',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary,
            style: context.fonts.interface(
              fontSize: 13,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final monthWidth =
                  (constraints.maxWidth - AppSpacing.md * (_monthsPerRow - 1)) /
                  _monthsPerRow;
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  for (var month = 1; month <= 12; month++)
                    SizedBox(
                      width: monthWidth,
                      child: _HeatmapMonth(heatmap: heatmap, month: month),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          const _HeatmapLegend(),
        ],
      ),
    );
  }

  /// Fill for a square at [level] — the accent at rising strength, and the
  /// divider (a faint but present square) for a past day with nothing.
  static Color cellColor(AppColors colors, int level) {
    if (level <= 0) return colors.divider.withValues(alpha: 0.6);
    const alphas = [0.3, 0.5, 0.75, 1.0];
    return colors.accent.withValues(alpha: alphas[level - 1]);
  }
}

/// One month of [_ReadingHeatmapView]: its initial, then a Monday-first
/// seven-column grid of day squares.
class _HeatmapMonth extends StatelessWidget {
  const _HeatmapMonth({required this.heatmap, required this.month});

  final ReadingHeatmap heatmap;
  final int month;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isCurrentMonth =
        heatmap.today.year == heatmap.year && heatmap.today.month == month;
    final blanks = heatmap.leadingBlanks(month);
    final length = heatmap.daysInMonth(month);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _monthName(month - 1).toLowerCase(),
          style: context.fonts.interface(
            fontSize: 11,
            fontWeight: isCurrentMonth ? FontWeight.w600 : FontWeight.w400,
            color: isCurrentMonth ? colors.accent : colors.secondaryText,
          ),
        ),
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (context, constraints) {
            final cell =
                (constraints.maxWidth - _ReadingHeatmapView._cellGap * 6) / 7;
            return Wrap(
              spacing: _ReadingHeatmapView._cellGap,
              runSpacing: _ReadingHeatmapView._cellGap,
              children: [
                for (var i = 0; i < blanks; i++)
                  SizedBox(width: cell, height: cell),
                for (var day = 1; day <= length; day++)
                  _HeatmapCell(
                    size: cell,
                    date: DateTime(heatmap.year, month, day),
                    heatmap: heatmap,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _HeatmapCell extends StatelessWidget {
  const _HeatmapCell({
    required this.size,
    required this.date,
    required this.heatmap,
  });

  final double size;
  final DateTime date;
  final ReadingHeatmap heatmap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (heatmap.isFuture(date)) {
      return SizedBox(width: size, height: size);
    }
    final isToday = date == heatmap.today;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _ReadingHeatmapView.cellColor(colors, heatmap.levelFor(date)),
        borderRadius: BorderRadius.circular(size * 0.25),
        border: isToday
            ? Border.all(color: colors.primaryText, width: 1)
            : null,
      ),
    );
  }
}

/// "less ▢▢▢▢▢ more" — the key to [_ReadingHeatmapView]'s shading.
class _HeatmapLegend extends StatelessWidget {
  const _HeatmapLegend();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = context.fonts.interface(
      fontSize: 11,
      color: colors.secondaryText,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('less', style: style),
        const SizedBox(width: 6),
        for (var level = 0; level <= ReadingHeatmap.maxLevel; level++) ...[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _ReadingHeatmapView.cellColor(colors, level),
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),
          const SizedBox(width: 3),
        ],
        const SizedBox(width: 3),
        Text('more', style: style),
      ],
    );
  }
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
          style: context.fonts.body(
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
            style: context.fonts.interface(
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
