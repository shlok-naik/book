import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/book_series.dart';
import '../controllers/library_controller.dart';
import '../library_scope.dart';

/// A picker over every series the reader has made
/// ([LibraryController.mySeries]), checked for the one this book is
/// already filed under — tapping a series files it there, tapping the
/// one already selected takes it out of it. A book is only ever in one
/// series at a time, unlike tags. Never makes a new series itself: that's
/// `make series` or the library's "+" panel, so a reader with none yet is
/// pointed there instead of typing one in here.
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
  /// Series ids mid-toggle, so a second tap while one is still saving is
  /// ignored rather than sent twice.
  final _pending = <String>{};

  Future<void> _toggle(
    LibraryController library,
    String title,
    BookSeries series,
    bool selected,
  ) async {
    if (_pending.contains(series.id)) return;
    setState(() => _pending.add(series.id));
    AppHaptics.selection();
    try {
      if (selected) {
        await library.removeFromSeries(title);
      } else {
        await library.addToSeries(title, series.name);
      }
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'SeriesSelectionSheet',
        'Toggling a series failed unexpectedly.',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (mounted) setState(() => _pending.remove(series.id));
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
                      style: GoogleFonts.jetBrainsMono(
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
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        height: 1.5,
                        color: colors.secondaryText,
                      ),
                    )
                  else if (entry == null)
                    Text(
                      "This book isn't on your shelf anymore.",
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        height: 1.5,
                        color: colors.secondaryText,
                      ),
                    )
                  else
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final one in series)
                          _SelectableSeriesChip(
                            series: one,
                            selected: entry.seriesId == one.id,
                            busy: _pending.contains(one.id),
                            onTap: () => _toggle(
                              library,
                              entry.book.title,
                              one,
                              entry.seriesId == one.id,
                            ),
                          ),
                      ],
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

class _SelectableSeriesChip extends StatelessWidget {
  const _SelectableSeriesChip({
    required this.series,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final BookSeries series;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: busy ? 0.6 : 1,
      child: Semantics(
        button: true,
        selected: selected,
        label: selected
            ? 'Remove from series ${series.name}'
            : 'Add to series ${series.name}',
        excludeSemantics: true,
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs + 2,
            ),
            decoration: BoxDecoration(
              color: selected ? colors.accent.withValues(alpha: 0.14) : null,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: selected ? colors.accent : colors.divider,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  Icon(Icons.check, size: 14, color: colors.accent),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Text(
                  series.name,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 13,
                    color: colors.primaryText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
