import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/library_book.dart';

/// One book in the grid: cover, title, and its progress readout.
///
/// The readout adapts to what we know. With a page count it's a teal bar
/// plus a percentage; without one (Google Books frequently omits it) it
/// degrades to "page N" with no bar, rather than faking a denominator.
///
/// To a screen reader the tile is one node, not six. Read as separate
/// fragments a shelf becomes "Dune", "Frank Herbert", "34/300 · 11%",
/// then five unlabelled star icons — technically complete and useless to
/// listen to. [_spokenSummary] says the same thing as one sentence.
class BookTile extends StatelessWidget {
  const BookTile({super.key, required this.entry, required this.cover});

  final LibraryBook entry;

  /// The cover widget, injected so the tile stays presentation-only and
  /// the grid decides how covers are sized/dimmed.
  final Widget cover;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final completion = entry.completion;

    return Semantics(
      container: true,
      label: _spokenSummary(),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cover,
          const SizedBox(height: AppSpacing.sm),
          Text(
            entry.book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.fraunces(
              fontSize: 14,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            entry.book.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 11, color: colors.secondaryText),
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
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              color: entry.isFinished ? colors.accent : colors.secondaryText,
            ),
          ),
          // Only ever set on a finished book (LibraryController.rateBook
          // enforces that), so no separate isFinished check is needed here.
          if (entry.rating != null) ...[
            const SizedBox(height: 2),
            _StarRating(rating: entry.rating!, color: colors.accent),
          ],
        ],
      ),
    );
  }

  /// The whole tile as one sentence. Deliberately not the same string as
  /// [_progressLabel]: "34/300 · 11%" is a compact glyph for the eye, and
  /// a screen reader would say it as "thirty-four slash three hundred
  /// middle dot eleven percent".
  String _spokenSummary() {
    final buffer = StringBuffer('${entry.book.title} by ${entry.book.author}.');

    if (entry.isFinished) {
      buffer.write(' Finished.');
    } else {
      final total = entry.pageCount;
      if (entry.currentPage == 0) {
        buffer.write(' Not started.');
      } else if (total == null) {
        buffer.write(' On page ${entry.currentPage}.');
      } else {
        final percent = ((entry.completion ?? 0) * 100).round();
        buffer.write(' Page ${entry.currentPage} of $total, $percent percent.');
      }
    }

    final rating = entry.rating;
    if (rating != null) {
      // "4 stars", not "4.0 stars".
      final stars = rating == rating.roundToDouble()
          ? rating.toStringAsFixed(0)
          : rating.toString();
      buffer.write(' Rated $stars out of 5.');
    }

    return buffer.toString();
  }

  String _progressLabel() {
    if (entry.isFinished) return 'finished';

    final total = entry.pageCount;
    if (total == null) {
      // No denominator to divide by — show the raw page instead.
      return entry.currentPage == 0 ? 'not started' : 'pg ${entry.currentPage}';
    }
    final percent = ((entry.completion ?? 0) * 100).round();
    return '${entry.currentPage}/$total · $percent%';
  }
}

/// A `rate <book> <stars>` rating: five stars (full, half, or outline)
/// plus the number itself. The icons alone read fine at a glance for a
/// whole rating, but a half star at 12px is easy to misread as full or
/// empty — the number next to it is what actually says "4.5" rather
/// than leaving it to a squint at the icon shape.
class _StarRating extends StatelessWidget {
  const _StarRating({required this.rating, required this.color});

  final double rating;
  final Color color;

  static const _starCount = 5;
  static const _size = 12.0;
  static const _gap = 1.0;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _starCount; i++) ...[
          if (i > 0) const SizedBox(width: _gap),
          Icon(_iconFor(i), size: _size, color: color),
        ],
        const SizedBox(width: AppSpacing.xs),
        Text(
          _formatRating(rating),
          style: GoogleFonts.jetBrainsMono(fontSize: 11, color: color),
        ),
      ],
    );
  }

  /// Star [i] is full once [rating] reaches its whole position, half if
  /// it reaches the half-star just before that, else outline.
  IconData _iconFor(int i) {
    final threshold = i + 1;
    if (rating >= threshold) return Icons.star;
    if (rating >= threshold - 0.5) return Icons.star_half;
    return Icons.star_border;
  }

  /// Drops a trailing ".0" ("5" rather than "5.0") but keeps a real half
  /// ("4.5") — mirrors `LogCommandParser`'s own formatting so the
  /// confirmation pill and this label never disagree.
  static String _formatRating(double rating) {
    return rating == rating.roundToDouble()
        ? rating.toInt().toString()
        : rating.toStringAsFixed(1);
  }
}

/// Hairline progress track. Kept as a plain container pair rather than a
/// [LinearProgressIndicator] so it inherits the design-system colors and
/// radius exactly.
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
            // Animated so a progress update reads as movement rather
            // than a jump when the `update` command lands.
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
