/// The two edition formats the detail page offers. Everything else Google
/// Books knows about — magazines, audiobook listings, study guides — is
/// filtered out before it is ever cached (see `EditionFilter`), and the
/// `book_editions.format` check constraint refuses anything else outright.
enum EditionFormat {
  ebook,
  physical;

  String get wireValue => name;

  static EditionFormat? fromWire(Object? value) {
    for (final format in EditionFormat.values) {
      if (format.wireValue == value) return format;
    }
    return null;
  }
}

/// One edition of a cached book — a row of the shared `book_editions`
/// table, or (before it has been written there) a candidate built from a
/// Google Books search result, in which case [id] is null.
class BookEdition {
  const BookEdition({
    this.id,
    required this.googleBooksId,
    required this.title,
    required this.author,
    required this.format,
    this.subtitle,
    this.publisher,
    this.publishedDate,
    this.pageCount,
    this.language,
    this.isbn13,
    this.isbn10,
    this.coverUrl,
  });

  /// `book_editions.id` — what `user_books.owned_edition_id` points at.
  /// Null only for a candidate that hasn't been cached yet; such an
  /// edition can be shown but not selected.
  final String? id;

  final String googleBooksId;
  final String title;
  final String? subtitle;
  final String author;
  final EditionFormat format;
  final String? publisher;

  /// Google's verbatim date string — see `Book.publishedDate`.
  final String? publishedDate;
  final int? pageCount;
  final String? language;
  final String? isbn13;
  final String? isbn10;
  final String? coverUrl;

  /// The four-digit year, when the date string starts with one.
  String? get year {
    final date = publishedDate;
    if (date == null || date.length < 4) return null;
    final year = date.substring(0, 4);
    return int.tryParse(year) == null ? null : year;
  }

  /// Parses a `book_editions` row. Null (not a throw) for a row missing
  /// something required, so one bad row drops out of the list instead of
  /// failing the whole editions section — same convention as
  /// `ReadingEvent.fromRow`.
  static BookEdition? fromRow(Map<String, dynamic> row) {
    final id = row['id'];
    final googleBooksId = row['google_books_id'];
    final title = row['title'];
    final format = EditionFormat.fromWire(row['format']);
    if (id is! String ||
        googleBooksId is! String ||
        title is! String ||
        title.isEmpty ||
        format == null) {
      return null;
    }
    final rawPages = row['page_count'];
    return BookEdition(
      id: id,
      googleBooksId: googleBooksId,
      title: title,
      subtitle: _text(row['subtitle']),
      author: _text(row['author']) ?? 'Unknown author',
      format: format,
      publisher: _text(row['publisher']),
      publishedDate: _text(row['published_date']),
      pageCount: rawPages is num && rawPages > 0 ? rawPages.toInt() : null,
      language: _text(row['language']),
      isbn13: _text(row['isbn_13']),
      isbn10: _text(row['isbn_10']),
      coverUrl: _text(row['cover_url']),
    );
  }

  /// The JSON shape `cache_book_editions` expects for each element.
  Map<String, Object?> toRpcJson() => {
    'google_books_id': googleBooksId,
    'title': title,
    'subtitle': subtitle,
    'author': author,
    'format': format.wireValue,
    'publisher': publisher,
    'published_date': publishedDate,
    'page_count': pageCount,
    'language': language,
    'isbn_13': isbn13,
    'isbn_10': isbn10,
    'cover_url': coverUrl,
  };

  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
