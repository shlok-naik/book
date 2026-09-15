import 'book.dart';
import 'book_edition.dart';
import 'user_book.dart';

/// A catalogue [Book] paired with the reader's [UserBook] progress —
/// the single view-model the library UI renders. Built by joining
/// `user_books` with its embedded `books` row and, when the reader has
/// picked one, the `book_editions` row they own.
class LibraryBook {
  const LibraryBook({
    required this.book,
    required this.progress,
    this.ownedEdition,
  });

  /// The work as cached — shared by every reader. What title matching,
  /// Google Books lookups and the journal key off; never edition-specific.
  final Book book;
  final UserBook progress;

  /// The edition the reader says they own (`progress.ownedEditionId`),
  /// embedded in the shelf query so its cover and page count are known
  /// from the first frame, without an editions fetch. Null when none is
  /// picked — or, briefly, for a row created locally before a reload.
  final BookEdition? ownedEdition;

  /// [book] as *this reader's copy* — the owned edition's cover, pages,
  /// publisher, date, ISBN and language over the work's. What every
  /// surface that shows the book should render; see [Book.withEdition].
  Book get displayBook {
    final edition = ownedEdition;
    return edition == null ? book : book.withEdition(edition);
  }

  String get id => progress.id;
  int get currentPage => progress.currentPage;

  /// The owned edition's length when it has one, else the work's — so
  /// progress, validation and "finished = last page" all follow the copy
  /// the reader is actually reading.
  int? get pageCount => displayBook.pageCount;

  /// True once the book has been marked finished, either explicitly
  /// (`finish <book>`) or by logging a page at/after the last one.
  bool get isFinished => progress.isFinished;

  bool get isReading => progress.status == ReadingStatus.reading;

  /// `move <book> tbr` — queued, never opened yet.
  bool get isToBeRead => progress.status == ReadingStatus.toBeRead;

  /// `move <book> dnf` — dropped.
  bool get isDnf => progress.status == ReadingStatus.dnf;

  /// `rate <book> <stars>`. Can only be *set* on a finished book (see
  /// `LibraryController.rateBook`), but survives a later move off the
  /// finished shelf rather than being thrown away — so a surface that
  /// shows it should still check [isFinished], as `BookTile` does.
  double? get rating => progress.rating;

  /// Where the reader is with this book. Also which built-in section it is
  /// shown in — unless it is on a custom shelf ([shelfId]).
  ReadingStatus get status => progress.status;

  /// The custom shelf this book is shown on, or null — see
  /// `UserBook.shelfId`.
  String? get shelfId => progress.shelfId;

  /// The series this book is filed under, private to this reader — see
  /// `UserBook.seriesId`. Resolve its display name through
  /// `LibraryController.seriesLabelFor`/`seriesById`.
  String? get seriesId => progress.seriesId;
  double? get seriesPosition => progress.seriesPosition;

  /// How many times this book has been restarted after finishing — see
  /// `UserBook.rereadCount`.
  int get rereadCount => progress.rereadCount;

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

  LibraryBook copyWith({
    Book? book,
    UserBook? progress,
    BookEdition? ownedEdition,
    bool clearOwnedEdition = false,
  }) {
    return LibraryBook(
      book: book ?? this.book,
      progress: progress ?? this.progress,
      ownedEdition: clearOwnedEdition
          ? null
          : ownedEdition ?? this.ownedEdition,
    );
  }
}
