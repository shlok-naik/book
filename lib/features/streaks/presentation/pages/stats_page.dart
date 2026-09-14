import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/purchases/plan_controller.dart';
import '../../../../core/purchases/purchases_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../goals/domain/reading_goal.dart';
import '../../../goals/presentation/goal_scope.dart';
import '../../../goals/presentation/widgets/goal_progress_view.dart';
import '../../../library/domain/reading_event.dart';
import '../../../library/presentation/library_scope.dart';
import '../../../paywall/presentation/pages/paywall_page.dart';
import '../../../shell/presentation/widgets/top_bar.dart';
import '../../domain/reading_stats.dart';
import '../controllers/streaks_controller.dart';

/// Gap between one day's entries and the next day's label.
const _daySpacing = AppSpacing.lg;

/// Gap between one entry and the next inside the same day.
const _entrySpacing = AppSpacing.sm;

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
/// only ever changed from settings), then numbers about the shelf (books
/// and pages read), four charts (books finished per month, pages read per
/// month, pace toward the goal, and how the shelf breaks down), then genres
/// and the reading journal — every command read back as the line it was
/// typed as, grouped under the day it happened, newest day first.
///
/// Everything but the journal is free and comes straight from
/// [ReadingStats] over the books `LibraryController` already holds, so it
/// updates the moment a command lands; only the journal needs the year of
/// `reading_events` [StreaksController] loads — and only the journal is
/// cactus pro. A free reader sees every chart but a faded, inert preview
/// where the journal would be (see [_LockedJournal]), the same
/// discoverability-without-access treatment settings gives "themes and
/// icons".
class StatsPage extends StatefulWidget {
  const StatsPage({super.key, this.purchases});

  /// Injection point for tests: a fake wrapping fake customer info
  /// instead of the real RevenueCat SDK. Null in the app.
  final PurchasesService? purchases;

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

  late final PurchasesService _purchases =
      widget.purchases ?? const PurchasesService();

  /// Whether the journal is unlocked. Fails closed — unknown (not yet
  /// checked, or the store unreachable) reads the same as "no", so a
  /// slow or offline entitlement check never leaks the journal to a
  /// free reader for even a moment.
  bool _isPro = false;

  /// True while a tap on the locked journal has a paywall or entitlement
  /// check in flight, so a second tap can't stack another paywall on
  /// top of the first.
  bool _checkingJournalAccess = false;

  @override
  void initState() {
    super.initState();
    PlanController.isPro.addListener(_onPlanChanged);
    unawaited(_refreshProStatus());
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
    _resetSubscription = library.resets.listen(
      (_) => unawaited(controller.reload(DateTime.now().year)),
    );
  }

  @override
  void dispose() {
    PlanController.isPro.removeListener(_onPlanChanged);
    _eventSubscription?.cancel();
    _clearedSubscription?.cancel();
    _resetSubscription?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _onPlanChanged() => unawaited(_refreshProStatus());

  /// [PlanController.isPro] first — the same debug override `HomePage`
  /// checks before gating `remember`/`recommend` — then, for a reader it
  /// says is free, the real RevenueCat entitlement.
  Future<void> _refreshProStatus() async {
    final isPro = PlanController.isPro.value || await _hasProEntitlement();
    if (!mounted) return;
    setState(() => _isPro = isPro);
  }

  Future<bool> _hasProEntitlement() async {
    try {
      return _purchases.isPro(await _purchases.customerInfo);
    } on Object {
      // Includes an SDK that was never configured — see [_refreshProStatus]
      // for why an unknown entitlement means "not pro" here.
      return false;
    }
  }

  /// Opens the paywall from the locked journal preview, then rechecks
  /// entitlement — a reader who just bought pro sees the journal unlock
  /// immediately rather than needing to leave the page and come back.
  Future<void> _unlockJournal() async {
    if (_checkingJournalAccess) return;
    setState(() => _checkingJournalAccess = true);
    try {
      await showPaywallPopup(context, purchases: widget.purchases);
      if (mounted) await _refreshProStatus();
    } finally {
      if (mounted) setState(() => _checkingJournalAccess = false);
    }
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
                    editable: false,
                    progress: stats.goalProgress(goals.goal),
                  )
                else if (goalError != null)
                  _LoadFailure(message: goalError, onRetry: goals.load),
                const SizedBox(height: AppSpacing.xl),
                _StatGrid(stats: stats),
                const SizedBox(height: AppSpacing.xl),
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
                _PaceChart(stats: stats, goal: stats.goalProgress(goals.goal)),
                const SizedBox(height: AppSpacing.xl),
                const _Heading('your shelf'),
                const SizedBox(height: AppSpacing.md),
                _ShelfDonut(stats: stats),
                if (stats.genres.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xl),
                  const _Heading('genres'),
                  const SizedBox(height: AppSpacing.md),
                  _Genres(genres: stats.genres),
                ],
                const SizedBox(height: AppSpacing.xl),
                const _Heading('journal'),
                const SizedBox(height: AppSpacing.md),
                if (!_isPro)
                  _LockedJournal(
                    busy: _checkingJournalAccess,
                    onTap: _unlockJournal,
                  )
                else if (controller != null)
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

/// Two columns of numbers, straight from the shelf.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats});

  final ReadingStats stats;

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
        style: GoogleFonts.jetBrainsMono(
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
                      style: GoogleFonts.jetBrainsMono(
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
        style: GoogleFonts.jetBrainsMono(
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
              style: GoogleFonts.jetBrainsMono(
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
    this.dashed = false,
    this.filled = false,
    this.strokeWidth = 2.5,
  });

  final List<double?> values;
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
            Offset(
              line.values.length == 1
                  ? 0
                  : size.width * i / (line.values.length - 1),
              size.height * (1 - (value / maxY).clamp(0.0, 1.0)),
            )
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

      if (!line.dashed) {
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

    if (running == 0 && goal == null) {
      return Text(
        'finish a book to start tracking your pace.',
        style: GoogleFonts.jetBrainsMono(
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
            Row(
              children: [
                _LegendSwatch(color: colors.accent),
                const SizedBox(width: 6),
                Text('you', style: _legendStyle(colors, colors.primaryText)),
                const SizedBox(width: AppSpacing.md),
                _LegendSwatch(color: colors.secondaryText, dashed: true),
                const SizedBox(width: 6),
                Text(
                  'steady pace',
                  style: _legendStyle(colors, colors.secondaryText),
                ),
                const Spacer(),
                Text(
                  goal.paceLabel(DateTime.now()),
                  style: _legendStyle(colors, colors.accent),
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

  static TextStyle _legendStyle(AppColors colors, Color color) =>
      GoogleFonts.jetBrainsMono(fontSize: 12, color: color);
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
        style: GoogleFonts.jetBrainsMono(
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
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: colors.primaryText,
                      ),
                    ),
                    Text(
                      total == 1 ? 'book' : 'books',
                      style: GoogleFonts.jetBrainsMono(
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
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 13,
                                color: colors.primaryText,
                              ),
                            ),
                          ),
                          Text(
                            '${s.count}',
                            style: GoogleFonts.jetBrainsMono(
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

/// What a free reader sees where the journal would be: the same
/// [_DayEntries] the real journal renders, faded and inert, over invented
/// entries rather than the reader's own — so the preview never leaks a
/// real title or date to a reader who hasn't unlocked it — plus a line
/// naming the way out. The whole block is one tap target, the same
/// visible-but-locked treatment `_CustomisationSection` (settings' "themes
/// and icons" row) gives a pro feature: faded rather than hidden, so a
/// free reader knows the journal exists before they ever pay for it.
class _LockedJournal extends StatelessWidget {
  const _LockedJournal({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  static final _preview = [
    (date: DateTime(2026, 9, 12), lines: const ['started The Hobbit']),
    (
      date: DateTime(2026, 9, 10),
      lines: const ['read up to page 140 in Dune', 'rated Dune 4.5 stars'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label:
          'Reading journal, locked. Upgrade to cactus pro to unlock. '
          'Double tap to upgrade.',
      excludeSemantics: true,
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
                    for (final (i, day) in _preview.indexed) ...[
                      if (i > 0) const SizedBox(height: _daySpacing),
                      _DayEntries(date: day.date, lines: day.lines),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'cactus pro unlocks your full reading journal — tap to upgrade',
              style: GoogleFonts.jetBrainsMono(
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
