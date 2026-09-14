import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../domain/library_book.dart';
import 'book_cover.dart';

/// A mosaic of up to four of a series' own covers, at the same footprint
/// as one [BookCover] — one book fills it whole, two split it left/right,
/// three give one half to the first and split the other half top/bottom
/// between the next two, four make a plain 2×2 grid. Always the shelf
/// grid's own grouped-series tile; the row above the shelves uses it only
/// when `SeriesTileStyleController.patchwork` says to.
class SeriesPatchworkCover extends StatelessWidget {
  const SeriesPatchworkCover({super.key, required this.entries});

  final List<LibraryBook> entries;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final covers = entries.take(4).toList();

    return AspectRatio(
      aspectRatio: BookCover.aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: ColoredBox(
          // Reads as a hairline seam between patches — each patch insets
          // itself by half a gap, so this only shows through the middle.
          color: colors.divider,
          child: _layout(covers),
        ),
      ),
    );
  }

  Widget _layout(List<LibraryBook> covers) {
    Widget patch(LibraryBook entry) => _Patch(entry: entry);
    Widget gap({required bool vertical}) =>
        SizedBox(width: vertical ? 0 : 1.5, height: vertical ? 1.5 : 0);

    return switch (covers.length) {
      0 => const SizedBox.shrink(),
      1 => patch(covers[0]),
      2 => Row(
        children: [
          Expanded(child: patch(covers[0])),
          gap(vertical: false),
          Expanded(child: patch(covers[1])),
        ],
      ),
      3 => Row(
        children: [
          Expanded(child: patch(covers[0])),
          gap(vertical: false),
          Expanded(
            child: Column(
              children: [
                Expanded(child: patch(covers[1])),
                gap(vertical: true),
                Expanded(child: patch(covers[2])),
              ],
            ),
          ),
        ],
      ),
      _ => Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: patch(covers[0])),
                gap(vertical: false),
                Expanded(child: patch(covers[1])),
              ],
            ),
          ),
          gap(vertical: true),
          Expanded(
            child: Row(
              children: [
                Expanded(child: patch(covers[2])),
                gap(vertical: false),
                Expanded(child: patch(covers[3])),
              ],
            ),
          ),
        ],
      ),
    };
  }
}

/// One cell of [SeriesPatchworkCover] — no aspect ratio of its own, so it
/// fills whatever rectangle the mosaic gives it rather than letterboxing.
class _Patch extends StatelessWidget {
  const _Patch({required this.entry});

  final LibraryBook entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final url = entry.displayBook.coverUrl;
    if (url == null || url.isEmpty) {
      return ColoredBox(color: colors.surface);
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, _, _) => ColoredBox(color: colors.surface),
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : ColoredBox(color: colors.surface),
    );
  }
}

/// The original look: up to three covers fanned diagonally behind one
/// another, at the same footprint as one [BookCover]. What the row above
/// the shelves shows unless `SeriesTileStyleController.patchwork` is on.
class SeriesFanCover extends StatelessWidget {
  const SeriesFanCover({super.key, required this.entries});

  final List<LibraryBook> entries;

  @override
  Widget build(BuildContext context) {
    final covers = entries.take(3).toList();
    return AspectRatio(
      aspectRatio: BookCover.aspectRatio,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Stack(
            children: [
              for (final (i, entry) in covers.indexed.toList().reversed)
                Positioned(
                  left: i * (width * 0.18),
                  top: i * 4.0,
                  bottom: 0,
                  child: SizedBox(
                    width: width * 0.6 - i * 4,
                    child: BookCover(
                      title: entry.book.title,
                      author: entry.book.author,
                      coverUrl: entry.displayBook.coverUrl,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
