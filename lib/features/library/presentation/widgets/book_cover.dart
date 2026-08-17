import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
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
  });

  final String title;
  final String author;
  final String? coverUrl;

  /// Finished books are shown slightly faded, so the in-progress shelf
  /// stays the visually dominant one.
  final bool dimmed;

  static const aspectRatio = 2 / 3;

  @override
  Widget build(BuildContext context) {
    final url = coverUrl;

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Opacity(
        opacity: dimmed ? 0.55 : 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: url == null || url.isEmpty
              ? _CoverPlaceholder(title: title, author: author)
              : Image.network(
                  url,
                  fit: BoxFit.cover,
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
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({required this.title, required this.author});

  final String title;
  final String author;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

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
            style: GoogleFonts.fraunces(
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
            style: GoogleFonts.inter(fontSize: 11, color: colors.secondaryText),
          ),
        ],
      ),
    );
  }
}
