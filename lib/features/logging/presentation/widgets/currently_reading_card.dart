import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../library/domain/library_book.dart';
import '../../../library/presentation/widgets/book_cover.dart';

/// The book the reader is most recently active on, sitting above the
/// streak readout on the add tab. Cover on the left, then the title and
/// — directly under it, not beside it — the progress readout, so it
/// reads top-to-bottom as "this book, this far in" rather than as two
/// columns competing for attention.
///
/// Deliberately no card chrome (no fill, no rounded corners) — the
/// streak/memory pages next door are both plain journals, not boxed
/// cards, and a filled rounded box here would be the one card-shaped
/// thing in an app that otherwise never uses that language.
class CurrentlyReadingCard extends StatelessWidget {
  const CurrentlyReadingCard({super.key, required this.entry});

  final LibraryBook entry;

  static const _coverWidth = 56.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final completion = entry.completion;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _coverWidth,
          child: BookCover(
            title: entry.book.title,
            author: entry.book.author,
            // The owned edition's cover when the reader picked one.
            coverUrl: entry.displayBook.coverUrl,
            isbn: entry.displayBook.isbn13 ?? entry.displayBook.isbn10,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'currently reading',
                style: context.fonts.interface(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.secondaryText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                entry.book.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.fonts.bookTitle(
                  fontSize: 16,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (completion != null) ...[
                _ProgressBar(
                  value: completion,
                  color: colors.accent,
                  track: colors.divider,
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              Text(
                _progressLabel(),
                style: context.fonts.interface(
                  fontSize: 12,
                  color: colors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _progressLabel() {
    final total = entry.pageCount;
    if (total == null) {
      return entry.currentPage == 0
          ? 'not started'
          : 'page ${entry.currentPage}';
    }
    final percent = ((entry.completion ?? 0) * 100).round();
    return 'page ${entry.currentPage} of $total · $percent%';
  }
}

/// Same hairline-track recipe as the library grid's own progress bar
/// (`BookTile`'s private `_ProgressBar`) — kept as its own small copy
/// rather than a shared import across features, but identical in look:
/// a plain container pair inheriting the design-system colors and
/// radius exactly, animated so an `update` reads as movement.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.value,
    required this.color,
    required this.track,
  });

  final double value;
  final Color color;
  final Color track;

  static const _height = 3.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth * value.clamp(0.0, 1.0);
        return Stack(
          children: [
            Container(
              height: _height,
              decoration: BoxDecoration(
                color: track,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              height: _height,
              width: width,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
          ],
        );
      },
    );
  }
}
