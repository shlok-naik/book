import 'book.dart';
import 'library_book.dart';
import 'user_book.dart';

/// A row of the shared `book_series` table.
class BookSeries {
  const BookSeries({required this.id, required this.name});

  final String id;
  final String name;

  static const maxNameLength = 80;

  /// Trimmed, inner whitespace collapsed — the same normalisation the
  /// database's unique index uses, so "The  Expanse " is "The Expanse".
  static String normalizeName(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ');

  bool matches(String other) =>
      normalizeName(name).toLowerCase() == normalizeName(other).toLowerCase();

  static BookSeries? fromRow(Map<String, dynamic> row) {
    final id = row['id'];
    final name = row['name'];
    if (id is! String || name is! String || name.trim().isEmpty) return null;
    return BookSeries(id: id, name: name.trim());
  }

  /// Series order: numbered books by number, then unnumbered ones by title.
  static List<Book> sortBooks(Iterable<Book> books) {
    return [...books]..sort((a, b) {
      final pa = a.seriesPosition;
      final pb = b.seriesPosition;
      if (pa != null && pb != null && pa != pb) return pa.compareTo(pb);
      if (pa != null && pb == null) return -1;
      if (pa == null && pb != null) return 1;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
  }

  /// `start series <series>`: the first book in series order the reader
  /// hasn't finished or dropped — the one to read next. Null when every
  /// book the catalogue knows about in this series is done.
  ///
  /// [shelf] maps a catalogue book id to the reader's row for it.
  static Book? nextToRead(
    List<Book> seriesBooks,
    Map<String, LibraryBook> shelf,
  ) {
    for (final book in sortBooks(seriesBooks)) {
      final status = shelf[book.id]?.status;
      if (status == ReadingStatus.finished || status == ReadingStatus.dnf) {
        continue;
      }
      return book;
    }
    return null;
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

  /// Groups every shelf book filed under a named series, series with the
  /// most recently touched book first (the shelf's own order).
  static List<SeriesGroup> fromShelf(Iterable<LibraryBook> shelf) {
    final byId = <String, List<LibraryBook>>{};
    final names = <String, String>{};
    for (final entry in shelf) {
      final id = entry.book.seriesId;
      final name = entry.book.seriesName;
      if (id == null || name == null) continue;
      (byId[id] ??= []).add(entry);
      names[id] = name;
    }
    return [
      for (final MapEntry(key: id, value: entries) in byId.entries)
        SeriesGroup(
          id: id,
          name: names[id]!,
          entries: [
            for (final book in BookSeries.sortBooks(entries.map((e) => e.book)))
              entries.firstWhere((entry) => entry.book.id == book.id),
          ],
        ),
    ];
  }
}
