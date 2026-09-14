import '../../library/domain/book_series.dart';
import '../../library/domain/library_book.dart';
import '../../library/domain/user_book.dart';
import 'csv_codec.dart';
import 'goodreads_import.dart';

/// Builds the CSV the settings "export library" row shares.
///
/// Columns use Goodreads' own names, so the file opens anywhere that reads
/// a Goodreads export — including this app's import, which makes export
/// then import round-trip: tags travel as Bookshelves, comments as My Review
/// (joined by [GoodreadsImport.commentSeparator]), and the extra columns
/// (Current Page, Series, Series Number) are read back too.
///
/// Never includes anything that isn't the reader's own library — no ids,
/// no account details.
abstract final class LibraryExport {
  static const header = [
    'Title',
    'Author',
    'ISBN',
    'ISBN13',
    'My Rating',
    'Number of Pages',
    'Current Page',
    'Date Read',
    'Date Added',
    'Exclusive Shelf',
    'Bookshelves',
    'My Review',
    'Series',
    'Series Number',
    'Owned Edition',
  ];

  static String build(
    List<LibraryBook> books, {
    Map<String, List<String>> tagsByBook = const {},
    Map<String, List<String>> commentsByBook = const {},
    Map<String, String> seriesNamesById = const {},
  }) {
    final rows = <List<String>>[header];
    for (final entry in books) {
      final book = entry.displayBook;
      final edition = entry.ownedEdition;
      rows.add([
        entry.book.title,
        entry.book.author,
        book.isbn10 ?? '',
        book.isbn13 ?? '',
        entry.isFinished && entry.rating != null ? _number(entry.rating!) : '0',
        book.pageCount?.toString() ?? '',
        entry.currentPage.toString(),
        entry.isFinished ? _date(entry.progress.finishedAt) : '',
        _date(entry.progress.startedAt),
        shelfName(entry.status),
        (tagsByBook[entry.id] ?? const []).join(', '),
        (commentsByBook[entry.id] ?? const []).join(
          GoodreadsImport.commentSeparator,
        ),
        entry.seriesId == null ? '' : seriesNamesById[entry.seriesId] ?? '',
        entry.seriesPosition == null
            ? ''
            : BookSeries.formatPosition(entry.seriesPosition!),
        edition == null
            ? ''
            : [
                edition.format.name,
                ?edition.publisher,
                ?edition.publishedDate,
              ].join(' · '),
      ]);
    }
    return CsvCodec.encode(rows);
  }

  /// Goodreads' exclusive shelf names; "did-not-finish" reads back as DNF.
  static String shelfName(ReadingStatus status) => switch (status) {
    ReadingStatus.finished => 'read',
    ReadingStatus.reading => 'currently-reading',
    ReadingStatus.toBeRead => 'to-read',
    ReadingStatus.dnf => 'did-not-finish',
  };

  /// "cactus-library-2026-09-13.csv".
  static String fileName(DateTime now) =>
      'cactus-library-${now.year}-${_pad(now.month)}-${_pad(now.day)}.csv';

  static String _date(DateTime? date) {
    if (date == null) return '';
    final local = date.toLocal();
    return '${local.year}/${_pad(local.month)}/${_pad(local.day)}';
  }

  static String _pad(int value) => value.toString().padLeft(2, '0');

  static String _number(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}
