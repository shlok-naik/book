import '../../library/domain/user_book.dart';
import 'csv_codec.dart';

/// One book read out of a Goodreads (or cactus) CSV export, before it has
/// been matched to a catalogue book.
class ImportRow {
  const ImportRow({
    required this.line,
    required this.title,
    required this.author,
    required this.status,
    this.isbn13,
    this.isbn10,
    this.rating,
    this.pages,
    this.currentPage,
    this.dateRead,
    this.dateAdded,
    this.tags = const [],
    this.comments = const [],
    this.series,
    this.seriesPosition,
  });

  /// 1-based row number in the file (the header is row 1), for reporting.
  final int line;
  final String title;
  final String author;
  final ReadingStatus status;
  final String? isbn13;
  final String? isbn10;

  /// 1–5; Goodreads' "0" (unrated) is null.
  final double? rating;
  final int? pages;

  /// Only cactus's own export has this; Goodreads has no page progress.
  final int? currentPage;
  final DateTime? dateRead;
  final DateTime? dateAdded;

  /// Goodreads' non-exclusive shelves, or cactus's tags.
  final List<String> tags;

  /// Goodreads' review, or cactus's comments.
  final List<String> comments;

  /// From a cactus "Series" column, or a Goodreads title like
  /// "Dune Messiah (Dune Chronicles, #2)".
  final String? series;
  final double? seriesPosition;

  String? get isbn => isbn13 ?? isbn10;
}

/// What a file turned into: the rows that could be read, and how many
/// couldn't (no title).
class ImportParseResult {
  const ImportParseResult({required this.rows, required this.skipped});

  final List<ImportRow> rows;
  final int skipped;
}

class ImportFormatException implements Exception {
  const ImportFormatException(this.message);

  final String message;

  @override
  String toString() => 'ImportFormatException: $message';
}

/// Reads a Goodreads library export ("My Books → Import and export →
/// Export library") — or a file this app exported, which uses the same
/// column names plus a few of its own — into [ImportRow]s.
///
/// The mapping, so it can be explained to a reader:
/// * **Exclusive Shelf** `read` → finished, `currently-reading` → reading,
///   `to-read` → to read; a custom exclusive shelf whose name says the book
///   was abandoned ("dnf", "did-not-finish", "abandoned", "gave-up", …) →
///   did not finish; any other custom shelf → to read.
/// * **My Rating** 1–5 is kept; 0 means unrated.
/// * **Date Read** becomes the finish date, **Date Added** the start date.
/// * **Bookshelves** other than the exclusive ones become tags, and
///   **My Review** a comment (with Goodreads' `<br/>` turned into line
///   breaks).
/// * ISBNs arrive wrapped as `="9780441013593"` and are unwrapped.
abstract final class GoodreadsImport {
  /// How the export joins several comments into one "My Review" cell.
  static const commentSeparator = '\n---\n';

  static const _dnfPattern =
      r'^(dnf|did[-_ ]?not[-_ ]?finish(ed)?|abandon(ed)?|gave[-_ ]?up|'
      r'quit|stopped[-_ ]?reading|unfinished)$';

  static final _seriesInTitle = RegExp(
    r'^(.*\S)\s*\(([^()#]+?),?\s*#(\d+(?:\.\d+)?)\)$',
  );

  static ImportParseResult parse(String csv) {
    final table = CsvCodec.decode(csv);
    if (table.isEmpty) {
      throw const ImportFormatException('That file is empty.');
    }

    final header = [for (final cell in table.first) cell.trim().toLowerCase()];
    int? column(String name) {
      final index = header.indexOf(name);
      return index == -1 ? null : index;
    }

    final titleColumn = column('title');
    if (titleColumn == null) {
      throw const ImportFormatException('Not a Goodreads export.');
    }
    final authorColumn = column('author');
    final isbnColumn = column('isbn');
    final isbn13Column = column('isbn13');
    final ratingColumn = column('my rating');
    final pagesColumn = column('number of pages');
    final currentPageColumn = column('current page');
    final dateReadColumn = column('date read');
    final dateAddedColumn = column('date added');
    final shelfColumn = column('exclusive shelf');
    final shelvesColumn = column('bookshelves');
    final reviewColumn = column('my review');
    final seriesColumn = column('series');
    final seriesNumberColumn = column('series number');

    final rows = <ImportRow>[];
    var skipped = 0;

    for (var r = 1; r < table.length; r++) {
      final cells = table[r];
      String cell(int? index) {
        if (index == null || index >= cells.length) return '';
        return _unescape(cells[index].trim());
      }

      var title = cell(titleColumn);
      if (title.isEmpty) {
        skipped++;
        continue;
      }

      String? series = _nonEmpty(cell(seriesColumn));
      double? seriesPosition = double.tryParse(cell(seriesNumberColumn));
      final inTitle = _seriesInTitle.firstMatch(title);
      if (inTitle != null) {
        title = inTitle.group(1)!.trim();
        series ??= inTitle.group(2)!.trim();
        seriesPosition ??= double.tryParse(inTitle.group(3)!);
      }

      final shelf = cell(shelfColumn).toLowerCase();
      final status = statusFor(shelf);
      final rating = double.tryParse(cell(ratingColumn));

      final tags = <String>{
        for (final name in cell(shelvesColumn).split(','))
          ?_tagFromShelf(name, shelf),
      }.toList();

      final comments = [
        for (final comment in _plainReview(
          cell(reviewColumn),
        ).split(commentSeparator))
          if (comment.trim().isNotEmpty) comment.trim(),
      ];

      rows.add(
        ImportRow(
          line: r + 1,
          title: title,
          author: _nonEmpty(cell(authorColumn)) ?? '',
          status: status,
          isbn13: _isbn(cell(isbn13Column)),
          isbn10: _isbn(cell(isbnColumn)),
          rating: rating != null && rating > 0 && rating <= 5 ? rating : null,
          pages: _positiveInt(cell(pagesColumn)),
          currentPage: int.tryParse(cell(currentPageColumn)),
          dateRead: parseDate(cell(dateReadColumn)),
          dateAdded: parseDate(cell(dateAddedColumn)),
          tags: tags,
          comments: comments,
          series: series,
          seriesPosition: seriesPosition != null && seriesPosition > 0
              ? seriesPosition
              : null,
        ),
      );
    }

    return ImportParseResult(rows: rows, skipped: skipped);
  }

  static ReadingStatus statusFor(String exclusiveShelf) {
    final shelf = exclusiveShelf.trim().toLowerCase();
    return switch (shelf) {
      'read' => ReadingStatus.finished,
      'currently-reading' => ReadingStatus.reading,
      'to-read' || '' => ReadingStatus.toBeRead,
      _ when RegExp(_dnfPattern).hasMatch(shelf) => ReadingStatus.dnf,
      _ => ReadingStatus.toBeRead,
    };
  }

  /// A non-exclusive shelf as a tag, or null for the built-in exclusive
  /// shelves (already the book's status) and the book's own exclusive one.
  static String? _tagFromShelf(String name, String exclusiveShelf) {
    final tag = name.trim();
    final lower = tag.toLowerCase();
    if (tag.isEmpty || tag.length > 40) return null;
    if (const {'read', 'currently-reading', 'to-read'}.contains(lower)) {
      return null;
    }
    if (lower == exclusiveShelf) return null;
    return tag;
  }

  /// Goodreads dates are `2024/03/17`; cactus writes `2024-03-17`.
  static DateTime? parseDate(String raw) {
    final match = RegExp(
      r'^(\d{4})[/-](\d{1,2})[/-](\d{1,2})$',
    ).firstMatch(raw.trim());
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(year, month, day, 12);
  }

  static String? _isbn(String raw) {
    final digits = raw.replaceAll(RegExp('[^0-9Xx]'), '').toUpperCase();
    return digits.length == 10 || digits.length == 13 ? digits : null;
  }

  static int? _positiveInt(String raw) {
    final value = int.tryParse(raw);
    return value != null && value > 0 ? value : null;
  }

  static String _plainReview(String review) => review
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp('<[^>]+>'), '')
      .trim();

  /// Undoes the formula guard [CsvCodec.encode] adds.
  static String _unescape(String value) =>
      RegExp(r"^'[=+\-@]").hasMatch(value) ? value.substring(1) : value;

  static String? _nonEmpty(String value) => value.isEmpty ? null : value;
}
