import 'book_edition.dart';
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
    this.subtitle,
    this.publisher,
    this.publishedDate,
    this.categories = const [],
    this.language,
    this.isbn10,
    this.isbn13,
    this.averageRating,
    this.ratingsCount,
    this.maturityRating,
    this.previewLink,
    this.detailsFetchedAt,
    this.editionsFetchedAt,
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

  /// The blurb. `cache_book` stores whatever the search endpoint returned
  /// (sometimes truncated); `cache_book_details` replaces it with the
  /// volume endpoint's full text once the detail page has been opened.
  final String? description;

  // ---- Extended info, filled in by `cache_book_details` -----------------
  // Every one of these is null (or empty) until [detailsFetchedAt] is set,
  // and may legitimately stay null afterwards — Google omits fields freely.

  final String? subtitle;
  final String? publisher;

  /// Google's own date string — "2005", "2005-08" or "2005-08-02". Kept
  /// verbatim rather than parsed into a [DateTime], which would have to
  /// invent a month and day that were never given.
  final String? publishedDate;

  final List<String> categories;

  /// BCP-47-ish language code ("en").
  final String? language;
  final String? isbn10;
  final String? isbn13;

  /// Google Books' community rating — not the reader's own (that lives on
  /// `UserBook.rating`).
  final double? averageRating;
  final int? ratingsCount;
  final String? maturityRating;
  final String? previewLink;

  /// When the extended info above was fetched from Google Books. Null is a
  /// cache *miss*: `BookDetailsService.detailsFor` goes to Google Books.
  /// Set is a hit even when every extended field came back empty, so a
  /// sparse volume doesn't re-query Google on every visit.
  final DateTime? detailsFetchedAt;

  /// Same idea for the `book_editions` cache — see
  /// `BookDetailsService.editionsFor`. Set (with zero editions stored)
  /// means "Google has no ebook/physical editions for this", not "unknown".
  final DateTime? editionsFetchedAt;

  bool get hasCachedDetails => detailsFetchedAt != null;
  bool get hasCachedEditions => editionsFetchedAt != null;

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
        "Couldn't read book.",
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
      subtitle: _nonEmpty(row['subtitle']),
      publisher: _nonEmpty(row['publisher']),
      publishedDate: _nonEmpty(row['published_date']),
      categories: [
        for (final category in (row['categories'] as List<dynamic>? ?? []))
          if (category is String && category.trim().isNotEmpty) category.trim(),
      ],
      language: _nonEmpty(row['language']),
      isbn10: _nonEmpty(row['isbn_10']),
      isbn13: _nonEmpty(row['isbn_13']),
      averageRating: _parseDouble(row['average_rating']),
      ratingsCount: switch (row['ratings_count']) {
        final num value => value.toInt(),
        final String value => int.tryParse(value),
        _ => null,
      },
      maturityRating: _nonEmpty(row['maturity_rating']),
      previewLink: _nonEmpty(row['preview_link']),
      detailsFetchedAt: _parseDate(row['details_fetched_at']),
      editionsFetchedAt: _parseDate(row['editions_fetched_at']),
    );
  }

  /// This work as the reader's own copy: [edition]'s cover, page count,
  /// publisher, publication date, ISBN and language.
  ///
  /// Title, author, blurb, genre and ratings stay the work's — they
  /// describe the book, not the printing, and commands match on the title
  /// (edition titles are often "DOCTOR SLEEP: NEW COVER SERIES").
  ///
  /// Falls back to the work only where a gap would break something: a
  /// cover (never a blank tile) and the page count (progress needs a
  /// total). Publisher, date and ISBN do *not* fall back — the work's
  /// publisher printed next to this edition's cover would be wrong, not
  /// just incomplete.
  Book withEdition(BookEdition edition) => Book(
    id: id,
    googleBooksId: googleBooksId,
    title: title,
    author: author,
    coverUrl: edition.coverUrl ?? coverUrl,
    pageCount: edition.pageCount ?? pageCount,
    description: description,
    subtitle: subtitle,
    publisher: edition.publisher,
    publishedDate: edition.publishedDate,
    categories: categories,
    language: edition.language ?? language,
    isbn10: edition.isbn10,
    isbn13: edition.isbn13,
    averageRating: averageRating,
    ratingsCount: ratingsCount,
    maturityRating: maturityRating,
    previewLink: previewLink,
    detailsFetchedAt: detailsFetchedAt,
    editionsFetchedAt: editionsFetchedAt,
  );

  /// Postgres `numeric` arrives over PostgREST as a String; accept both.
  static double? _parseDouble(Object? value) => switch (value) {
    final num number => number.toDouble(),
    final String text => double.tryParse(text),
    _ => null,
  };

  static DateTime? _parseDate(Object? value) =>
      value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;

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
