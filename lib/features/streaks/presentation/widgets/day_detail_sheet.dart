import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/date_pill.dart';
import '../../../library/domain/reading_event.dart';
import '../../domain/day_symbol.dart';
import 'day_symbol_mark.dart';

/// Opened from tapping a day-dot on the streaks grid — a standard modal
/// bottom sheet: full width, rounded top corners only, a drag handle,
/// sliding up from the bottom edge. Swipe down or tap outside to dismiss.
///
/// Lists every command logged that day, oldest first, each with the
/// same mark its dot earns on the grid — so a reader can see exactly
/// what added up to the shape they tapped on.
Future<void> showDayDetailSheet(
  BuildContext context,
  DateTime date, {
  List<ReadingEvent> events = const [],
}) {
  final colors = context.colors;

  return showModalBottomSheet<void>(
    context: context,
    // Lets the sheet grow past its old fixed minimum for a long day's
    // list, while [maxHeight] below still caps it — without this the
    // sheet stays pinned to its default (roughly half-screen) height and
    // a long list overflows past the bottom of it instead of scrolling.
    isScrollControlled: true,
    backgroundColor: colors.background,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    constraints: const BoxConstraints(maxWidth: double.infinity),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (context) {
      final screenHeight = MediaQuery.sizeOf(context).height;
      final minHeight = screenHeight * 0.32;
      final maxHeight = screenHeight * 0.75;

      return SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: minHeight,
            maxHeight: maxHeight,
          ),
          child: SizedBox(
            width: double.infinity,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.divider,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  DatePill(date: date),
                  const SizedBox(height: AppSpacing.lg),
                  if (events.isEmpty)
                    Text(
                      'Nothing logged this day.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: colors.secondaryText,
                      ),
                    )
                  else
                    for (final (i, event) in events.indexed) ...[
                      _EventRow(event: event),
                      if (i < events.length - 1)
                        const SizedBox(height: AppSpacing.sm),
                    ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// One logged command: its mark (same shape the grid draws for it), the
/// verb and book title, and the time it happened.
class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final ReadingEvent event;

  static const _markSize = 10.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      children: [
        SizedBox(
          width: _markSize,
          height: _markSize,
          child: Center(
            child: DaySymbolMark(
              symbol: DaySymbol.forType(event.type),
              diameter: _markSize,
              color: colors.accent,
              lineThickness: 2,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            '${_verb(event.type)} ${event.title ?? "a book"}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 14,
              color: colors.primaryText,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          _formatTime(event.occurredAt.toLocal()),
          style: GoogleFonts.jetBrainsMono(
            fontSize: 12,
            color: colors.secondaryText,
          ),
        ),
      ],
    );
  }

  static String _verb(ReadingEventType type) => switch (type) {
    ReadingEventType.start => 'started',
    ReadingEventType.update => 'updated',
    ReadingEventType.finish => 'finished',
    ReadingEventType.rate => 'rated',
    ReadingEventType.delete => 'removed',
  };

  /// `h:mm am/pm`, no leading zero on the hour — matches how the rest of
  /// the app avoids pulling in `intl` for a single format.
  static String _formatTime(DateTime time) {
    final hour24 = time.hour;
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = hour24 < 12 ? 'am' : 'pm';
    return '$hour12:$minute $period';
  }
}
