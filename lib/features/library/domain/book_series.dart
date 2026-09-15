import '../../../core/formatting/numbers.dart';
import 'collections.dart';
import 'library_book.dart';

/// A row of the reader's own `series` table — private to them, like a
/// [Shelf] or a [ReaderTag]. What a book is filed under lives on that
/// reader's own `user_books.series_id`/`series_position`, never on the
/// shared `books` row.
class BookSeries {
  const BookSeries({required this.id, required this.name});

  final String id;
  final String name;

  /// Trimmed, inner whitespace collapsed — the same normalisation the
  /// database's unique index uses, so "The  Expanse " is "The Expanse".
  static String normalizeName(String name) => CollectionNames.clean(name);

  bool matches(String other) =>
      normalizeName(name).toLowerCase() == normalizeName(other).toLowerCase();

  static BookSeries? fromRow(Map<String, dynamic> row) {
    final id = row['id'];
    final name = row['name'];
    if (id is! String || name is! String || name.trim().isEmpty) return null;
    return BookSeries(id: id, name: name.trim());
  }

  /// "2" for 2.0, "1.5" for 1.5.
  static String formatPosition(double position) =>
      formatCompactNumber(position);

  /// Series order: numbered books by number, then unnumbered ones by title.
  static List<LibraryBook> sortEntries(Iterable<LibraryBook> entries) {
    return [...entries]..sort((a, b) {
      final pa = a.seriesPosition;
      final pb = b.seriesPosition;
      if (pa != null && pb != null && pa != pb) return pa.compareTo(pb);
      if (pa != null && pb == null) return -1;
      if (pa == null && pb != null) return 1;
      return a.book.title.toLowerCase().compareTo(b.book.title.toLowerCase());
    });
  }
}

/// The reader's own books in one series, for the library's series row.
class SeriesGroup {
  const SeriesGroup({
    required this.id,
    required this.name,
    required this.entries,
  });

  final String id;
  final String name;

  /// The reader's books in this series, in series order.
  final List<LibraryBook> entries;

  int get finished => entries.where((entry) => entry.isFinished).length;

  /// "3 books · 1 finished".
  String get summary {
    final count = entries.length;
    final done = finished;
    final books = '$count ${count == 1 ? 'book' : 'books'}';
    return done == 0 ? books : '$books · $done finished';
  }

  /// Groups every shelf book filed under one of [mySeries] (the reader's
  /// own list — a series id on a book that has since been removed from
  /// the list groups under nothing), series with the most recently touched
  /// book first (the shelf's own order).
  static List<SeriesGroup> fromShelf(
    Iterable<LibraryBook> shelf,
    List<BookSeries> mySeries,
  ) {
    final byId = <String, List<LibraryBook>>{};
    for (final entry in shelf) {
      final id = entry.seriesId;
      if (id == null) continue;
      (byId[id] ??= []).add(entry);
    }
    final namesById = {for (final s in mySeries) s.id: s.name};
    return [
      for (final MapEntry(key: id, value: entries) in byId.entries)
        if (namesById[id] case final name?)
          SeriesGroup(
            id: id,
            name: name,
            entries: BookSeries.sortEntries(entries),
          ),
    ];
  }
}
