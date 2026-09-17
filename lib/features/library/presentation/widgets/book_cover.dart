import 'dart:async';
import 'dart:math' as math;

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
    this.isbn,
    this.dimmed = false,
    this.rereadCount = 0,
    this.finished = false,
  });

  final String title;
  final String author;
  final String? coverUrl;

  /// The book's ISBN, when known — where a cover comes from when Google
  /// has none (see [CoverImage]).
  final String? isbn;

  /// Finished books are shown slightly faded, so the in-progress shelf
  /// stays the visually dominant one.
  final bool dimmed;

  /// How many times this book has been restarted after finishing
  /// (`restart <book>`, or "read again" on the book page). 0 draws nothing;
  /// otherwise star stickers go in the corner — see [RereadStickers].
  final int rereadCount;

  /// Whether the book is finished right now — a finished re-read earns its
  /// second sticker.
  final bool finished;

  static const aspectRatio = 2 / 3;

  @override
  Widget build(BuildContext context) {
    final cover = Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: CoverImage(
          coverUrl: coverUrl,
          isbn: isbn,
          title: title,
          author: author,
          placeholder: _CoverPlaceholder(title: title, author: author),
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
                  child: RereadStickers(
                    rereadCount: rereadCount,
                    finished: finished,
                  ),
                ),
              ],
            ),
    );
  }
}

/// Star-shaped stickers for a re-read book. Restarting puts one on the
/// cover and finishing that pass adds a second: bronze for the first
/// re-read, silver for the second, gold for the third. It stops there — a
/// fourth re-read still counts, but the cover stays at two gold stars.
class RereadStickers extends StatelessWidget {
  const RereadStickers({
    super.key,
    required this.rereadCount,
    required this.finished,
  });

  final int rereadCount;
  final bool finished;

  static const _bronze = Color(0xFFCD7F32);
  static const _silver = Color(0xFFC0C0C0);
  static const _gold = Color(0xFFFFD700);

  static const size = 20.0;

  /// 1 bronze, 2 silver, 3+ gold.
  static int tierOf(int rereadCount) => rereadCount.clamp(1, 3);

  /// One sticker while the re-read is under way, two once it's finished.
  static int countOf({required bool finished}) => finished ? 2 : 1;

  @override
  Widget build(BuildContext context) {
    final tier = tierOf(rereadCount);
    final count = countOf(finished: finished);
    final color = switch (tier) {
      1 => _bronze,
      2 => _silver,
      _ => _gold,
    };
    final metal = switch (tier) {
      1 => 'bronze',
      2 => 'silver',
      _ => 'gold',
    };
    return Semantics(
      label: 'Read again: $count $metal ${count == 1 ? 'star' : 'stars'}',
      excludeSemantics: true,
      child: Row(
        key: ValueKey('reread-stickers-$metal-$count'),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            SizedBox(
              width: size,
              height: size,
              child: CustomPaint(painter: _StarPainter(color)),
            ),
          ],
        ],
      ),
    );
  }
}

class _StarPainter extends CustomPainter {
  const _StarPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.shortestSide / 2;
    final inner = outer * 0.48;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? outer : inner;
      final angle = -math.pi / 2 + i * math.pi / 5;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawShadow(path, Colors.black, 1.5, false);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black26
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  @override
  bool shouldRepaint(covariant _StarPainter oldDelegate) =>
      oldDelegate.color != color;
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

  /// The most the placeholder's own type scales by. A cover is a fixed
  /// shape, so at the largest reader text sizes its title cannot both scale
  /// and fit — and it doesn't need to: every surface that shows a cover
  /// prints the title beside it at full size, and a screen reader is given
  /// it either way.
  static const _maxTextScale = 1.3;

  Widget _labelled(BuildContext context, AppColors colors) {
    final scaler = MediaQuery.textScalerOf(context);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: _maxTextScale,
      child: _body(context, colors, scaler),
    );
  }

  Widget _body(BuildContext context, AppColors colors, TextScaler scaler) {
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

/// A cover picture, trying each place one might come from in turn and
/// showing [placeholder] while loading and when none works:
///
/// 1. the cover URL cached from Google Books, then
/// 2. Open Library's cover for the ISBN.
///
/// Google has no thumbnail for plenty of volumes (most `…ACAAJ` records),
/// and its image endpoint sometimes refuses a request outright; either
/// used to leave a placeholder where a real cover exists. Open Library's
/// `default=false` answers 404 rather than a blank image when it has
/// nothing, so a miss falls through to the placeholder instead of drawing
/// an empty rectangle. Only the ISBN is sent — never anything the reader
/// typed.
class CoverImage extends StatefulWidget {
  const CoverImage({
    super.key,
    required this.coverUrl,
    required this.isbn,
    required this.placeholder,
    this.fit = BoxFit.cover,
    this.title,
    this.author,
  });

  final String? coverUrl;
  final String? isbn;

  /// With [title], a book whose own sources both fail asks
  /// [titleCoverResolver] — Open Library, by title and author — before
  /// settling on the placeholder.
  final String? title;
  final String? author;

  /// Set once by the composition root (`main.dart`) to
  /// `OpenLibraryClient.coverFor`; null in tests, where no lookup happens.
  static Future<String?> Function({
    String? isbn,
    required String title,
    String? author,
  })?
  titleCoverResolver;
  final Widget placeholder;
  final BoxFit fit;

  /// Where to look, in order. Public for tests.
  static List<String> candidates(String? coverUrl, String? isbn) {
    final digits = isbn?.replaceAll(RegExp('[^0-9Xx]'), '');
    return [
      if (coverUrl != null && coverUrl.isNotEmpty) coverUrl,
      if (digits != null && (digits.length == 10 || digits.length == 13))
        'https://covers.openlibrary.org/b/isbn/$digits-M.jpg?default=false',
    ];
  }

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
  State<CoverImage> createState() => _CoverImageState();
}

class _CoverImageState extends State<CoverImage> {
  /// Which of [CoverImage.candidates] is being tried.
  int _attempt = 0;

  /// Open Library's cover by title, once the book's own sources ran out.
  String? _resolved;
  bool _resolving = false;

  /// Bumped whenever the book changes, so a title lookup started for the
  /// previous book can't land on this one.
  int _generation = 0;

  @override
  void didUpdateWidget(CoverImage old) {
    super.didUpdateWidget(old);
    if (old.coverUrl != widget.coverUrl ||
        old.isbn != widget.isbn ||
        old.title != widget.title ||
        old.author != widget.author) {
      _generation++;
      _attempt = 0;
      _resolved = null;
      _resolving = false;
    }
  }

  Future<void> _resolve() async {
    final resolver = CoverImage.titleCoverResolver;
    final title = widget.title;
    if (_resolving || resolver == null || title == null) return;
    _resolving = true;
    final generation = _generation;
    try {
      final url = await resolver(title: title, author: widget.author);
      if (mounted && url != null && generation == _generation) {
        setState(() => _resolved = url);
      }
    } on Object {
      // A missing cover is only cosmetic — the placeholder stays.
    }
  }

  @override
  Widget build(BuildContext context) {
    final urls = [
      ...CoverImage.candidates(widget.coverUrl, widget.isbn),
      ?_resolved,
    ];
    if (_attempt >= urls.length) {
      if (_resolved == null) unawaited(_resolve());
      return widget.placeholder;
    }

    return LayoutBuilder(
      builder: (context, constraints) => Image.network(
        urls[_attempt],
        // Keyed so a fallback is a fresh image, not the failed one reused.
        key: ValueKey(urls[_attempt]),
        fit: widget.fit,
        // Decoded at the size it's drawn, not the file's own.
        cacheWidth: CoverImage._decodeWidth(context, constraints),
        errorBuilder: (context, _, _) {
          // Try the next source after this frame; the placeholder holds
          // the tile's footprint meanwhile.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _attempt < urls.length) {
              setState(() => _attempt++);
            }
          });
          return widget.placeholder;
        },
        // Hold the placeholder while bytes are in flight so the tile never
        // flashes empty.
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : widget.placeholder,
      ),
    );
  }
}
