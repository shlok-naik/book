import 'library_exception.dart';

/// Where the reader is with a book.
enum ReadingStatus {
  reading,
  finished;

  /// Column value stored in Supabase. Kept as a lowercase string so the
  /// table stays readable in the dashboard.
  String get wireValue => name;

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

  bool get isFinished => status == ReadingStatus.finished;

  UserBook copyWith({
    int? currentPage,
    ReadingStatus? status,
    DateTime? finishedAt,
    double? rating,
  }) {
    return UserBook(
      id: id,
      bookId: bookId,
      currentPage: currentPage ?? this.currentPage,
      status: status ?? this.status,
      startedAt: startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      rating: rating ?? this.rating,
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
      rating: _parseRating(row['rating']),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is DateTime) return value;
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  /// Postgres `numeric` columns come back over the REST API as a String
  /// (to avoid float rounding), not a num — normalize either shape.
  static double? _parseRating(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
