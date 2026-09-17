import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../library/data/google_book.dart';
import '../../../library/domain/library_book.dart';
import '../../../library/presentation/widgets/book_cover.dart';

/// A book in a list: a small cover, the title and author, an optional
/// [caption] under them and an optional [trailing] control. One semantics
/// node carrying [semanticsLabel], a button that runs [onTap].
///
/// Shared by the search tab's results and the book picker, for the reader's
/// own books ([BookRow.shelf]) and Google Books volumes ([BookRow.volume])
/// alike, so both lists read the same.
class BookRow extends StatelessWidget {
  const BookRow({
    super.key,
    required this.title,
    required this.author,
    required this.cover,
    required this.semanticsLabel,
    required this.onTap,
    this.caption,
    this.trailing,
  });

  factory BookRow.shelf({
    Key? key,
    required LibraryBook entry,
    required String shelfName,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final book = entry.displayBook;
    return BookRow(
      key: key,
      title: book.title,
      author: book.author,
      caption: 'on your shelf · $shelfName',
      semanticsLabel:
          '${book.title} by ${book.author}. On your $shelfName shelf.',
      cover: BookCover(
        title: book.title,
        author: book.author,
        coverUrl: book.coverUrl,
        isbn: book.isbn13 ?? book.isbn10,
        rereadCount: entry.rereadCount,
        finished: entry.isFinished,
      ),
      onTap: onTap,
      trailing: trailing,
    );
  }

  factory BookRow.volume({
    Key? key,
    required GoogleBook volume,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final year = publishedYear(volume.publishedDate);
    return BookRow(
      key: key,
      title: volume.title,
      author: volume.authorLine,
      caption: year,
      semanticsLabel: [
        '${volume.title} by ${volume.authorLine}',
        ?year,
      ].join(', '),
      cover: BookCover(
        title: volume.title,
        author: volume.authorLine,
        coverUrl: volume.thumbnailUrl,
        isbn: volume.isbn13 ?? volume.isbn10,
      ),
      onTap: onTap,
      trailing: trailing,
    );
  }

  final String title;
  final String author;
  final String? caption;
  final Widget cover;
  final String semanticsLabel;
  final VoidCallback onTap;
  final Widget? trailing;

  static const coverWidth = 44.0;

  /// The four-digit year out of Google's "2005", "2005-08" or "2005-08-02".
  static String? publishedYear(String? date) =>
      date == null ? null : RegExp(r'\d{4}').firstMatch(date)?.group(0);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final caption = this.caption;
    final trailing = this.trailing;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: semanticsLabel,
            excludeSemantics: true,
            onTap: onTap,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  children: [
                    SizedBox(width: coverWidth, child: cover),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.fonts.bookTitle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: colors.primaryText,
                            ),
                          ),
                          Text(
                            author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.fonts.body(
                              fontSize: 13,
                              color: colors.secondaryText,
                            ),
                          ),
                          if (caption != null)
                            Text(
                              caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.fonts.interface(
                                fontSize: 11,
                                color: colors.secondaryText,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// A small section heading over a list — "on your shelf", "google books".
class ListHeading extends StatelessWidget {
  const ListHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.md,
          bottom: AppSpacing.sm,
        ),
        child: Text(
          text,
          style: context.fonts.interface(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.colors.secondaryText,
          ),
        ),
      ),
    );
  }
}
