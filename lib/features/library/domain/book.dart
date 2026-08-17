import 'library_exception.dart';

/// A book as it lives in the Supabase `books` cache table — the shared
/// catalogue entry, with no per-user reading state on it (that lives on
/// [UserBook]). One row per Google Books volume.
class Book {
  const Book({
    required this.id,
    required this.googleBooksId,
    required this.title,
    required this.author,
    this.coverUrl,
    this.pageCount,
    this.description,
  });

  /// Supabase primary key (uuid). This — not [googleBooksId] — is what
  /// `user_books.book_id` points at.
  final String id;

  /// Google Books volume id, the stable key we de-duplicate the cache on.
  final String googleBooksId;

  final String title;

  /// Google Books returns a list of authors; we store them pre-joined
  /// (", ") because every surface in the app renders them as one line.
  final String author;

  /// Thumbnail URL. Nullable — plenty of volumes have no cover art, and
  /// the UI falls back to a placeholder rather than breaking the layout.
  final String? coverUrl;

  /// Total pages. Nullable, and when it is null a percentage progress
  /// cannot be computed — the UI degrades to "page N" and only an
  /// explicit `finish` command can complete the book.
  final int? pageCount;

  final String? description;

  /// Parses a `books` row.
  ///
  /// Defensive on purpose: a row that lost its primary key or title is a
  /// schema/permission problem, not something the UI can render, so it
  /// fails loudly as a [RemoteDataException] instead of silently
  /// producing a half-empty card.
  factory Book.fromRow(Map<String, dynamic> row) {
    final id = row['id'];
    final title = row['title'];
    if (id is! String || id.isEmpty || title is! String || title.isEmpty) {
      throw RemoteDataException(
        "We couldn't read that book from the library.",
        cause: 'books row missing id/title: $row',
      );
    }

    // Ints can arrive as num (or even String) depending on the column
    // type and the transport, so normalize rather than hard-cast.
    final rawPageCount = row['page_count'];
    final pageCount = switch (rawPageCount) {
      final int value => value,
      final num value => value.toInt(),
      final String value => int.tryParse(value),
      _ => null,
    };

    return Book(
      id: id,
      googleBooksId: row['google_books_id'] as String? ?? '',
      title: title,
      author: row['author'] as String? ?? unknownAuthor,
      coverUrl: _nonEmpty(row['cover_url']),
      pageCount: (pageCount != null && pageCount > 0) ? pageCount : null,
      description: _nonEmpty(row['description']),
    );
  }

  static const unknownAuthor = 'Unknown author';

  /// Treats empty strings as absent — Supabase columns that were written
  /// from an empty Google Books field come back as '' rather than null,
  /// and an empty cover URL must hit the placeholder path.
  static String? _nonEmpty(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  String toString() => 'Book($googleBooksId, "$title")';
}
