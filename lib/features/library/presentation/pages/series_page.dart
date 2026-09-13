import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../settings/presentation/widgets/settings_header.dart';
import '../../domain/book.dart';
import '../../domain/book_series.dart';
import '../../domain/library_book.dart';
import '../../domain/library_exception.dart';
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

/// Every book filed under one series, in series order — including ones the
/// reader doesn't have yet, since series are shared. Books on the shelf say
/// where the reader is with them and open their detail page; the rest are
/// marked "not on your shelf".
///
/// Until the shared list loads (or if it can't), the reader's own books in
/// the series are shown, so the page is never blank.
class SeriesPage extends StatefulWidget {
  const SeriesPage({super.key, required this.seriesId, required this.name});

  final String seriesId;
  final String name;

  @override
  State<SeriesPage> createState() => _SeriesPageState();
}

class _SeriesPageState extends State<SeriesPage> {
  List<Book>? _books;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final books = await LibraryScope.read(
        context,
      ).series.booksInSeries(widget.seriesId);
      if (!mounted) return;
      setState(() {
        _books = books;
        _loading = false;
      });
    } on LibraryException catch (error) {
      AppLogger.error('SeriesPage', 'Loading a series failed.', error: error);
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final library = LibraryScope.of(context);
    final shelf = {for (final entry in library.books) entry.book.id: entry};
    final own = [
      for (final entry in library.books)
        if (entry.book.seriesId == widget.seriesId) entry.book,
    ];
    final books = BookSeries.sortBooks(_books ?? own);
    final error = _error;

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
              SettingsHeader(title: widget.name),
              const SizedBox(height: AppSpacing.lg),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          error,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: colors.secondaryText,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _loading ? null : _load,
                        child: Text(
                          'try again',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 13,
                            color: colors.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                  itemCount: books.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: AppSpacing.lg, color: colors.divider),
                  itemBuilder: (context, index) => _SeriesRow(
                    book: books[index],
                    entry: shelf[books[index].id],
                  ),
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
  const _SeriesRow({required this.book, required this.entry});

  final Book book;
  final LibraryBook? entry;

  static String _statusOf(LibraryBook? entry) {
    if (entry == null) return 'not on your shelf';
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
    final entry = this.entry;
    final position = book.seriesPosition;
    final shown = entry?.displayBook ?? book;
    final status = _statusOf(entry);

    return Semantics(
      button: entry != null,
      label:
          '${position == null ? '' : 'Book ${Book.formatSeriesPosition(position)}: '}'
          '${book.title} by ${book.author}. $status.',
      excludeSemantics: true,
      child: InkWell(
        onTap: entry == null ? null : () => openBookDetail(context, entry),
        child: Opacity(
          opacity: entry == null ? 0.6 : 1,
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  position == null
                      ? ''
                      : '#${Book.formatSeriesPosition(position)}',
                  style: GoogleFonts.jetBrainsMono(
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
                  coverUrl: shown.coverUrl,
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
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.primaryText,
                      ),
                    ),
                    Text(
                      book.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: colors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        color: entry?.isReading ?? false
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
      ),
    );
  }
}
