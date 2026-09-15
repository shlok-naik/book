import 'library_exception.dart';

/// Where the reader is with a book.
enum ReadingStatus {
  /// `move <book> tbr` — queued, never opened yet.
  toBeRead,
  reading,
  finished,

  /// `move <book> dnf` — dropped. A reason, if the reader wants to
  /// give one, is a comment on the book (`add comment <comment> <book>`).
  dnf;

  /// Column value stored in Supabase. Lowercase, matching the name for
  /// [reading]/[finished]/[dnf] so the table stays readable in the
  /// dashboard; [toBeRead] needs its own mapping since its Dart name
  /// isn't already snake_case.
  String get wireValue => switch (this) {
    ReadingStatus.toBeRead => 'to_be_read',
    ReadingStatus.reading => 'reading',
    ReadingStatus.finished => 'finished',
    ReadingStatus.dnf => 'dnf',
  };

  /// Unknown/unmapped values fall back to [reading] — a bad status is
  /// not worth failing a whole library load over.
  static ReadingStatus fromWire(Object? value) {
    return ReadingStatus.values.firstWhere(
      (status) => status.wireValue == value,
      orElse: () => ReadingStatus.reading,
    );
  }
}

/// A row of the Supabase `user_books` table: the reader's progress
/// against one [Book]. Auth is out of scope, so there is no user column
/// yet — every row belongs to the single local reader.
class UserBook {
  const UserBook({
    required this.id,
    required this.bookId,
    required this.currentPage,
    required this.status,
    this.startedAt,
    this.finishedAt,
    this.rating,
    this.ownedEditionId,
    this.shelfPosition,
    this.shelfId,
    this.seriesId,
    this.seriesPosition,
    this.rereadCount = 0,
    this.imported = false,
  });

  final String id;
  final String bookId;

  /// Last logged page. Always >= 0; validation happens before writing.
  final int currentPage;

  final ReadingStatus status;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  /// `rate <book> <stars>`. Half-star granularity, 0 (exclusive) to 5.
  /// Null until rated — [LibraryController.rateBook] is what enforces
  /// that a rating can only be set on a finished book; this column
  /// itself allows one on any row.
  final double? rating;

  /// The `book_editions` row the reader says they own — picked on the
  /// book detail page. Null until picked. The database's composite foreign
  /// key guarantees it is an edition of *this* book.
  final String? ownedEditionId;

  /// Manual order inside its shelf section, written by drag-to-reorder.
  /// Null means "never placed by hand" — see `ShelfRules.sortSection` for
  /// how placed and unplaced rows interleave, and the `touch_updated_at`
  /// trigger for why a status change resets it to null server-side.
  final double? shelfPosition;

  /// The custom shelf (`make shelf`) this book is shown on, or null when it
  /// sits on its [status] shelf. Independent of [status] — see `Shelf` — so
  /// only `move` and a drag on the library page ever change it; `finish`,
  /// `update` and friends leave a book on its custom shelf.
  final String? shelfId;

  /// The series (`make series`) this book is filed under, private to this
  /// reader — or null. Independent of [shelfId]/[status]; only `add series`
  /// ever changes it.
  final String? seriesId;

  /// Its number within [seriesId] — 1, 2, or 1.5 for a novella. Null when
  /// filed without a number, or not in a series at all.
  final double? seriesPosition;

  /// How many times this book has been restarted after finishing —
  /// `restart <book>` — driving the bronze/silver/gold cover badge.
  /// Never decreases; unrelated to [status].
  final int rereadCount;

  /// True for a row a Goodreads import created (`user_books.imported`).
  /// Imported books are history rather than reading done in the app: the
  /// stats page leaves them out of its monthly charts and uses them as the
  /// pace chart's baseline instead — see `ReadingStats`.
  final bool imported;

  bool get isFinished => status == ReadingStatus.finished;

  /// `clearFinishedAt`/`clearShelfPosition`/`clearOwnedEdition`/
  /// `clearShelfId`/`clearSeriesPosition` exist because a plain `null`
  /// argument can't be told apart from "not given" — and each of those
  /// genuinely needs to go back to null (a book moved off the finished
  /// shelf, a book moved into a new section, an edition deselected, a
  /// series re-filed with no number).
  UserBook copyWith({
    int? currentPage,
    ReadingStatus? status,
    DateTime? startedAt,
    DateTime? finishedAt,
    bool clearFinishedAt = false,
    double? rating,
    String? ownedEditionId,
    bool clearOwnedEdition = false,
    double? shelfPosition,
    bool clearShelfPosition = false,
    String? shelfId,
    bool clearShelfId = false,
    String? seriesId,
    bool clearSeriesId = false,
    double? seriesPosition,
    bool clearSeriesPosition = false,
    int? rereadCount,
  }) {
    return UserBook(
      id: id,
      bookId: bookId,
      currentPage: currentPage ?? this.currentPage,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: clearFinishedAt ? null : finishedAt ?? this.finishedAt,
      rating: rating ?? this.rating,
      ownedEditionId: clearOwnedEdition
          ? null
          : ownedEditionId ?? this.ownedEditionId,
      seriesId: clearSeriesId ? null : seriesId ?? this.seriesId,
      seriesPosition: clearSeriesPosition
          ? null
          : seriesPosition ?? this.seriesPosition,
      shelfPosition: clearShelfPosition
          ? null
          : shelfPosition ?? this.shelfPosition,
      shelfId: clearShelfId ? null : shelfId ?? this.shelfId,
      rereadCount: rereadCount ?? this.rereadCount,
      imported: imported,
    );
  }

  /// Parses a `user_books` row. Like [Book.fromRow], a row without its
  /// identifiers is unusable and raises a [RemoteDataException].
  factory UserBook.fromRow(Map<String, dynamic> row) {
    final id = row['id'];
    final bookId = row['book_id'];
    if (id is! String || id.isEmpty || bookId is! String || bookId.isEmpty) {
      throw RemoteDataException(
        "We couldn't read your reading progress.",
        cause: 'user_books row missing id/book_id: $row',
      );
    }

    final rawPage = row['current_page'];
    final page = switch (rawPage) {
      final int value => value,
      final num value => value.toInt(),
      final String value => int.tryParse(value) ?? 0,
      _ => 0,
    };

    return UserBook(
      id: id,
      bookId: bookId,
      currentPage: page < 0 ? 0 : page,
      status: ReadingStatus.fromWire(row['status']),
      startedAt: _parseDate(row['started_at']),
      finishedAt: _parseDate(row['finished_at']),
      rating: _parseDouble(row['rating']),
      ownedEditionId: row['owned_edition_id'] is String
          ? row['owned_edition_id'] as String
          : null,
      shelfPosition: _parseDouble(row['shelf_position']),
      shelfId: row['shelf_id'] is String ? row['shelf_id'] as String : null,
      seriesId: row['series_id'] is String ? row['series_id'] as String : null,
      seriesPosition: _parseDouble(row['series_position']),
      rereadCount: switch (row['reread_count']) {
        final int value => value,
        final num value => value.toInt(),
        _ => 0,
      },
      // Absent (the column not migrated yet, or an old cached row) reads
      // as not imported — every book counts, as it always did.
      imported: row['imported'] == true,
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is DateTime) return value;
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  /// Postgres `numeric` columns come back over the REST API as a String
  /// (to avoid float rounding), not a num — normalize either shape.
  static double? _parseDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
