import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../settings/presentation/widgets/settings_header.dart';
import '../../domain/book_series.dart';
import '../../domain/library_book.dart';
import '../../domain/user_book.dart';
import '../library_scope.dart';
import '../widgets/book_cover.dart';
import 'book_detail_page.dart';

/// Opens [SeriesPage] for a series the reader has books in.
Future<void> openSeries(BuildContext context, SeriesGroup group) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'series'),
      builder: (_) => SeriesPage(seriesId: group.id, name: group.name),
    ),
  );
}

/// Every book on the reader's shelf filed under one series, in series
/// order. Private to this reader — unlike a shared catalogue, there is no
/// "the rest of the series" to show for a book they don't have, so this is
/// just a live filter over their own shelf, never a network fetch.
class SeriesPage extends StatelessWidget {
  const SeriesPage({super.key, required this.seriesId, required this.name});

  final String seriesId;
  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final library = LibraryScope.of(context);
    final entries = BookSeries.sortEntries([
      for (final entry in library.books)
        if (entry.seriesId == seriesId) entry,
    ]);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsHeader(title: name),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: AppSpacing.lg, color: colors.divider),
                  itemBuilder: (context, index) =>
                      _SeriesRow(entry: entries[index]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeriesRow extends StatelessWidget {
  const _SeriesRow({required this.entry});

  final LibraryBook entry;

  static String _statusOf(LibraryBook entry) {
    final completion = entry.completion;
    return switch (entry.status) {
      ReadingStatus.finished => 'finished',
      ReadingStatus.toBeRead => 'to read',
      ReadingStatus.dnf => 'did not finish',
      ReadingStatus.reading =>
        completion == null
            ? 'reading · page ${entry.currentPage}'
            : 'reading · ${(completion * 100).round()}%',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final book = entry.displayBook;
    final position = entry.seriesPosition;
    final status = _statusOf(entry);

    return Semantics(
      button: true,
      label:
          '${position == null ? '' : 'Book ${BookSeries.formatPosition(position)}: '}'
          '${book.title} by ${book.author}. $status.',
      excludeSemantics: true,
      onTap: () => openBookDetail(context, entry),
      child: InkWell(
        onTap: () => openBookDetail(context, entry),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Text(
                position == null
                    ? ''
                    : '#${BookSeries.formatPosition(position)}',
                style: context.fonts.interface(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.secondaryText,
                ),
              ),
            ),
            SizedBox(
              width: 48,
              child: BookCover(
                title: book.title,
                author: book.author,
                coverUrl: book.coverUrl,
                isbn: book.isbn13 ?? book.isbn10,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.fonts.interface(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.primaryText,
                    ),
                  ),
                  Text(
                    book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.fonts.body(
                      fontSize: 13,
                      color: colors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    status,
                    style: context.fonts.interface(
                      fontSize: 12,
                      color: entry.isReading
                          ? colors.accent
                          : colors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
