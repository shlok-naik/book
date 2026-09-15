import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';

/// A book cover at the standard 2:3 book aspect ratio.
///
/// Covers are the one field most likely to be missing or broken — plenty
/// of Google Books volumes have no thumbnail, and a URL that 404s or
/// times out must not leave a hole in the grid. Both cases render the
/// same typographic placeholder (title + author on the surface color) so
/// every tile keeps its exact footprint either way.
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.title,
    required this.author,
    this.coverUrl,
    this.dimmed = false,
    this.rereadCount = 0,
  });

  final String title;
  final String author;
  final String? coverUrl;

  /// Finished books are shown slightly faded, so the in-progress shelf
  /// stays the visually dominant one.
  final bool dimmed;

  /// How many times this book has been restarted after finishing
  /// (`restart <book>`) — 0 draws nothing; 1/2/3+ draw a bronze/silver/gold
  /// medal in the corner. See `UserBook.rereadCount`.
  final int rereadCount;

  static const aspectRatio = 2 / 3;

  /// Physical pixels to decode a cover at for [constraints] — rounded up to
  /// a 64px step so a few pixels' difference between two places a cover is
  /// shown (a tile, a series fan) shares one decoded image instead of two.
  /// Null (decode at full size) when the width isn't bounded.
  static int? _decodeWidth(BuildContext context, BoxConstraints constraints) {
    final width = constraints.maxWidth;
    if (!width.isFinite || width <= 0) return null;
    final physical = width * MediaQuery.devicePixelRatioOf(context);
    return ((physical / 64).ceil() * 64).clamp(64, 2048);
  }

  @override
  Widget build(BuildContext context) {
    final url = coverUrl;

    final cover = Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: url == null || url.isEmpty
            ? _CoverPlaceholder(title: title, author: author)
            : LayoutBuilder(
                builder: (context, constraints) => Image.network(
                  url,
                  fit: BoxFit.cover,
                  // Decoded at the size it's drawn, not the file's own: a
                  // grid of full-resolution covers held every one of them
                  // in memory at full size and decoded them on the raster
                  // thread while scrolling.
                  cacheWidth: _decodeWidth(context, constraints),
                  // A failed download (offline, dead link, 403) falls
                  // back to the placeholder instead of Flutter's default
                  // broken-image icon.
                  errorBuilder: (context, _, _) =>
                      _CoverPlaceholder(title: title, author: author),
                  // Hold the placeholder while bytes are in flight so
                  // the tile never flashes empty.
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return _CoverPlaceholder(title: title, author: author);
                  },
                ),
              ),
      ),
    );

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: rereadCount <= 0
          ? cover
          : Stack(
              children: [
                Positioned.fill(child: cover),
                Positioned(
                  top: AppSpacing.xs,
                  right: AppSpacing.xs,
                  child: _RereadBadge(rereadCount: rereadCount),
                ),
              ],
            ),
    );
  }
}

/// The bronze/silver/gold medal for a book restarted 1/2/3+ times.
class _RereadBadge extends StatelessWidget {
  const _RereadBadge({required this.rereadCount});

  final int rereadCount;

  static const _bronze = Color(0xFFCD7F32);
  static const _silver = Color(0xFFC0C0C0);
  static const _gold = Color(0xFFFFD700);

  Color get _color => switch (rereadCount) {
    1 => _bronze,
    2 => _silver,
    _ => _gold,
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: switch (rereadCount) {
        1 => 'Read twice',
        2 => 'Read 3 times',
        final n => 'Read ${n + 1} times',
      },
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _color,
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: const Icon(
          Icons.workspace_premium,
          size: 14,
          color: Colors.black54,
        ),
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({required this.title, required this.author});

  final String title;
  final String author;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Too small for a readable title (a series list thumbnail): just
        // the blank cover, rather than text that overflows it.
        if (constraints.maxHeight < 96) {
          return ColoredBox(color: colors.surface);
        }
        return _labelled(context, colors);
      },
    );
  }

  Widget _labelled(BuildContext context, AppColors colors) {
    return Container(
      color: colors.surface,
      padding: const EdgeInsets.all(AppSpacing.sm),
      alignment: Alignment.bottomLeft,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: context.fonts.bookTitle(
              fontSize: 13,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.fonts.body(
              fontSize: 11,
              color: colors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}
