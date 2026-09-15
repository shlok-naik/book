import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../domain/library_book.dart';
import 'book_cover.dart';

/// A mosaic of a series' own covers, at the same footprint as one
/// [BookCover] (so the ratio stays 2:3 and a quadrant is itself
/// book-shaped, never a stretched sliver): one book fills the whole
/// tile; two or three sit one to a corner — top-left, top-right,
/// bottom-left, in that order — leaving the rest blank rather than
/// splitting the space between them; four fill all corners. Always the
/// shelf grid's own grouped-series tile; the row above the shelves uses
/// it only when `SeriesTileStyleController.patchwork` says to.
class SeriesPatchworkCover extends StatelessWidget {
  const SeriesPatchworkCover({super.key, required this.entries});

  final List<LibraryBook> entries;

  static const _gap = 1.5;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final covers = entries.take(4).toList();

    return AspectRatio(
      aspectRatio: BookCover.aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: covers.length <= 1
            ? (covers.isEmpty
                  ? ColoredBox(color: colors.surface)
                  : _Patch(entry: covers[0]))
            : ColoredBox(
                // Reads as a hairline seam between patches, and as the
                // fill for a blank corner — both insets leave this
                // showing through.
                color: colors.divider,
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(child: _cell(covers, 0)),
                          const SizedBox(width: _gap),
                          Expanded(child: _cell(covers, 1)),
                        ],
                      ),
                    ),
                    const SizedBox(height: _gap),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(child: _cell(covers, 2)),
                          const SizedBox(width: _gap),
                          Expanded(child: _cell(covers, 3)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _cell(List<LibraryBook> covers, int index) => index < covers.length
      ? _Patch(entry: covers[index])
      : Builder(
          builder: (context) => ColoredBox(color: context.colors.surface),
        );
}

/// One cell of [SeriesPatchworkCover] — no aspect ratio of its own, so it
/// fills whatever (book-shaped) rectangle the mosaic gives it. `BoxFit.cover`
/// crops to fit rather than distorting the image, so nothing here ever
/// stretches.
class _Patch extends StatelessWidget {
  const _Patch({required this.entry});

  final LibraryBook entry;

  @override
  Widget build(BuildContext context) {
    final book = entry.displayBook;
    return CoverImage(
      coverUrl: book.coverUrl,
      isbn: book.isbn13 ?? book.isbn10,
      placeholder: ColoredBox(color: context.colors.surface),
    );
  }
}

/// The original look: up to three covers fanned diagonally behind one
/// another. Sized to its own content — wider than a single [BookCover]
/// footprint, since the whole point is the cascade peeking out from
/// behind — so a caller must give it room rather than pinning it to one
/// cover's width. Every cover keeps its own natural 2:3 shape; nothing
/// here is squeezed to fill borrowed space. What the row above the
/// shelves shows unless `SeriesTileStyleController.patchwork` is on.
class SeriesFanCover extends StatelessWidget {
  const SeriesFanCover({super.key, required this.entries});

  final List<LibraryBook> entries;

  static const _coverWidth = 72.0;
  static const _spread = 22.0;

  @override
  Widget build(BuildContext context) {
    final covers = entries.take(3).toList();
    if (covers.isEmpty) return const SizedBox.shrink();
    final height = _coverWidth / BookCover.aspectRatio;

    return SizedBox(
      width: _coverWidth + _spread * (covers.length - 1),
      height: height,
      child: Stack(
        children: [
          for (final (i, entry) in covers.indexed.toList().reversed)
            Positioned(
              left: i * _spread,
              top: i * 4.0,
              child: SizedBox(
                width: _coverWidth - i * 4,
                height: height - i * 4,
                child: BookCover(
                  title: entry.book.title,
                  author: entry.book.author,
                  coverUrl: entry.displayBook.coverUrl,
                  isbn: entry.displayBook.isbn13 ?? entry.displayBook.isbn10,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
