import 'book.dart';
import 'user_book.dart';

/// A catalogue [Book] paired with the reader's [UserBook] progress —
/// the single view-model the library UI renders. Built by joining
/// `user_books` with its embedded `books` row.
class LibraryBook {
  const LibraryBook({required this.book, required this.progress});

  final Book book;
  final UserBook progress;

  String get id => progress.id;
  int get currentPage => progress.currentPage;
  int? get pageCount => book.pageCount;

  /// True once the book has been marked finished, either explicitly
  /// (`finish <book>`) or by logging a page at/after the last one.
  bool get isFinished => progress.isFinished;

  /// `rate <book> <stars>`. Only ever set on a finished book — see
  /// [UserBook.rating] — so the UI can treat a non-null value here as
  /// safe to render without re-checking [isFinished] itself.
  double? get rating => progress.rating;

  /// Completion in the 0..1 range, or null when the total page count is
  /// unknown (Google Books often omits it) — callers must handle null by
  /// showing "page N" instead of a percentage bar. Finished books read
  /// as 1.0 even without a page count so the UI never shows an empty bar
  /// on a completed book.
  double? get completion {
    if (isFinished) return 1;
    final total = pageCount;
    if (total == null || total <= 0) return null;
    return (currentPage / total).clamp(0.0, 1.0);
  }

  LibraryBook copyWith({Book? book, UserBook? progress}) {
    return LibraryBook(
      book: book ?? this.book,
      progress: progress ?? this.progress,
    );
  }
}
