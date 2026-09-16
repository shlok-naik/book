import 'package:flutter/material.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/book_series.dart';
import '../controllers/library_controller.dart';
import '../library_scope.dart';

/// A picker over every series the reader has made
/// ([LibraryController.mySeries]), checked for the one this book is
/// already filed under — tapping a series files it there, tapping the
/// one already selected takes it out of it. A book is only ever in one
/// series at a time, unlike tags. Each row carries its own `#n` number
/// field, read at the moment a series is applied (or re-applied, if
/// edited while already selected) — the same optional number `add series`
/// takes. Never makes a new series itself: that's `make series` or the
/// library's "+" panel, so a reader with none yet is pointed there
/// instead of typing one in here.
Future<void> showSeriesSelectionSheet(BuildContext context, String userBookId) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.surface,
    useSafeArea: true,
    isScrollControlled: true,
    // Named so it shows up in the analytics funnel.
    routeSettings: const RouteSettings(name: 'select_series'),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (_) => SeriesSelectionSheet(userBookId: userBookId),
  );
}

class SeriesSelectionSheet extends StatefulWidget {
  const SeriesSelectionSheet({super.key, required this.userBookId});

  final String userBookId;

  @override
  State<SeriesSelectionSheet> createState() => _SeriesSelectionSheetState();
}

class _SeriesSelectionSheetState extends State<SeriesSelectionSheet> {
  /// Series ids mid-write, so a second tap/submit while one is still
  /// saving is ignored rather than sent twice.
  final _pending = <String>{};

  /// One `#n` field's text per series, kept across rebuilds so typing
  /// isn't clobbered by the next one — seeded from the book's own
  /// position the first time a series is seen, never again after.
  final _positionControllers = <String, TextEditingController>{};

  TextEditingController _positionController(String seriesId, double? seeded) {
    return _positionControllers.putIfAbsent(
      seriesId,
      () => TextEditingController(
        text: seeded == null ? '' : BookSeries.formatPosition(seeded),
      ),
    );
  }

  double? _typedPosition(String seriesId) {
    final raw = _positionControllers[seriesId]?.text.trim();
    if (raw == null || raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  @override
  void dispose() {
    for (final controller in _positionControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _write(Future<void> Function() action, String seriesId) async {
    if (_pending.contains(seriesId)) return;
    setState(() => _pending.add(seriesId));
    AppHaptics.selection();
    try {
      await action();
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'SeriesSelectionSheet',
        'Saving a series failed unexpectedly.',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (mounted) setState(() => _pending.remove(seriesId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final media = MediaQuery.of(context);
    final library = LibraryScope.of(context);

    return AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        final entry = library.findById(widget.userBookId);
        final series = library.mySeries;

        return Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'select series',
                      style: context.fonts.interface(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (series.isEmpty)
                    Text(
                      "you haven't made any series yet — make one from the "
                      "library's + panel.",
                      style: context.fonts.body(
                        fontSize: 13,
                        height: 1.5,
                        color: colors.secondaryText,
                      ),
                    )
                  else if (entry == null)
                    Text(
                      'No longer on your shelf.',
                      style: context.fonts.body(
                        fontSize: 13,
                        height: 1.5,
                        color: colors.secondaryText,
                      ),
                    )
                  else
                    // Scrolls under the fixed heading: a Column of every
                    // series overflowed the sheet once there were more
                    // than fit, and the lower ones couldn't be reached.
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: [
                          for (final one in series) ...[
                            if (one != series.first)
                              const SizedBox(height: AppSpacing.sm),
                            _SeriesRow(
                              series: one,
                              selected: entry.seriesId == one.id,
                              busy: _pending.contains(one.id),
                              controller: _positionController(
                                one.id,
                                entry.seriesId == one.id
                                    ? entry.seriesPosition
                                    : null,
                              ),
                              onToggle: () => _write(() async {
                                if (entry.seriesId == one.id) {
                                  await library.removeFromSeriesById(
                                    entry.id,
                                    seriesName: one.name,
                                  );
                                } else {
                                  await library.addToSeriesById(
                                    entry.id,
                                    one.name,
                                    position: _typedPosition(one.id),
                                  );
                                }
                              }, one.id),
                              // Editing the number of a series this book is
                              // already in re-files it at the new number;
                              // typed before selecting, it's just waiting.
                              onSubmitPosition: entry.seriesId != one.id
                                  ? null
                                  : () => _write(
                                      () => library.addToSeriesById(
                                        entry.id,
                                        one.name,
                                        position: _typedPosition(one.id),
                                      ),
                                      one.id,
                                    ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SeriesRow extends StatelessWidget {
  const _SeriesRow({
    required this.series,
    required this.selected,
    required this.busy,
    required this.controller,
    required this.onToggle,
    required this.onSubmitPosition,
  });

  final BookSeries series;
  final bool selected;
  final bool busy;
  final TextEditingController controller;
  final VoidCallback onToggle;

  /// Re-files the book at the field's current number — only while it's
  /// already in this series; null otherwise, so submitting a number
  /// before selecting does nothing on its own.
  final VoidCallback? onSubmitPosition;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: busy ? 0.6 : 1,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              label: selected
                  ? 'Remove from series ${series.name}'
                  : 'Add to series ${series.name}',
              excludeSemantics: true,
              child: InkWell(
                onTap: busy ? null : onToggle,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm + 2,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? colors.accent.withValues(alpha: 0.14)
                        : null,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: selected ? colors.accent : colors.divider,
                    ),
                  ),
                  child: Row(
                    children: [
                      if (selected) ...[
                        Icon(Icons.check, size: 14, color: colors.accent),
                        const SizedBox(width: AppSpacing.xs),
                      ],
                      Expanded(
                        child: Text(
                          series.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.fonts.interface(
                            fontSize: 13,
                            color: colors.primaryText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // The "#n" column: a book's number within this series, read at
          // the moment the row above is tapped (or, once selected,
          // re-read on submit to re-file at a new number).
          SizedBox(
            width: 52,
            child: Semantics(
              label: '${series.name} number',
              textField: true,
              child: TextField(
                controller: controller,
                enabled: !busy,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onSubmitted: onSubmitPosition == null
                    ? null
                    : (_) => onSubmitPosition!(),
                style: context.fonts.interface(
                  fontSize: 13,
                  color: colors.primaryText,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '#n',
                  hintStyle: context.fonts.interface(
                    fontSize: 13,
                    color: colors.secondaryText,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.sm + 2,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: BorderSide(color: colors.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: BorderSide(color: colors.accent),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
