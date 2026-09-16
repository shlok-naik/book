import '../domain/book.dart';

/// A single search result from the Google Books API — trimmed to the
/// fields the library feature actually needs, not the full API shape.
class GoogleBook {
  const GoogleBook({
    required this.id,
    required this.title,
    required this.authors,
    this.thumbnailUrl,
    this.description,
    this.pageCount,
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
    this.printType,
    this.isEbook = false,
  });

  final String id;
  final String title;
  final List<String> authors;
  final String? thumbnailUrl;
  final String? description;

  /// Total pages, when the volume reports it. Needed to turn a logged
  /// page number into a completion percentage.
  final int? pageCount;

  // ---- Extended fields — used by the book detail page's info section and
  // by `EditionFilter` to tell an ebook from a physical book from a
  // magazine. All optional; Google omits any of them freely.

  final String? subtitle;
  final String? publisher;
  final String? publishedDate;
  final List<String> categories;
  final String? language;
  final String? isbn10;
  final String? isbn13;
  final double? averageRating;
  final int? ratingsCount;
  final String? maturityRating;
  final String? previewLink;

  /// `BOOK` or `MAGAZINE` (Google's only two values today).
  final String? printType;

  /// `saleInfo.isEbook` — Google's own statement that this volume is sold
  /// as an ebook.
  final bool isEbook;

  /// A book from the shared catalogue, as a volume — for rows that list
  /// cactus's own `books` (what other readers read) alongside Google's.
  factory GoogleBook.fromBook(Book book) => GoogleBook(
    id: book.googleBooksId,
    title: book.title,
    authors: [book.author],
    thumbnailUrl: book.coverUrl,
    description: book.description,
    pageCount: book.pageCount,
    subtitle: book.subtitle,
    publisher: book.publisher,
    publishedDate: book.publishedDate,
    categories: book.categories,
    language: book.language,
    isbn10: book.isbn10,
    isbn13: book.isbn13,
    averageRating: book.averageRating,
    ratingsCount: book.ratingsCount,
  );

  /// Authors joined the way the app renders them everywhere (one line).
  String get authorLine =>
      authors.isEmpty ? Book.unknownAuthor : authors.join(', ');

  /// Lenient by design: the API omits fields freely (no authors, no
  /// cover, no page count), and a missing field must not fail the parse.
  /// Only a structurally wrong payload — a non-object item — is fatal,
  /// and that is caught by the caller as a malformed response.
  factory GoogleBook.fromJson(Map<String, dynamic> json) {
    final volumeInfo =
        (json['volumeInfo'] as Map<String, dynamic>?) ?? const {};
    final imageLinks =
        (volumeInfo['imageLinks'] as Map<String, dynamic>?) ?? const {};

    final saleInfo = (json['saleInfo'] as Map<String, dynamic>?) ?? const {};
    final identifiers = <String, String>{
      for (final identifier
          in (volumeInfo['industryIdentifiers'] as List<dynamic>?) ?? const [])
        if (identifier is Map<String, dynamic> &&
            identifier['type'] is String &&
            identifier['identifier'] is String)
          identifier['type'] as String: identifier['identifier'] as String,
    };
    final rawRating = volumeInfo['averageRating'];
    final rawRatingsCount = volumeInfo['ratingsCount'];

    final rawPageCount = volumeInfo['pageCount'];
    final pageCount = switch (rawPageCount) {
      final int value => value,
      final num value => value.toInt(),
      _ => null,
    };

    return GoogleBook(
      id: json['id'] as String? ?? '',
      title: volumeInfo['title'] as String? ?? 'Untitled',
      authors:
          (volumeInfo['authors'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          const [],
      // Google serves thumbnails over plain http in some responses;
      // upgrade to https so iOS ATS / Android cleartext rules don't
      // silently blank the cover.
      thumbnailUrl: _httpsUrl(imageLinks['thumbnail'] as String?),
      description: volumeInfo['description'] as String?,
      pageCount: (pageCount != null && pageCount > 0) ? pageCount : null,
      subtitle: _text(volumeInfo['subtitle']),
      publisher: _text(volumeInfo['publisher']),
      publishedDate: _text(volumeInfo['publishedDate']),
      categories:
          (volumeInfo['categories'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          const [],
      language: _text(volumeInfo['language']),
      isbn10: identifiers['ISBN_10'],
      isbn13: identifiers['ISBN_13'],
      averageRating: rawRating is num ? rawRating.toDouble() : null,
      ratingsCount: rawRatingsCount is num ? rawRatingsCount.toInt() : null,
      maturityRating: _text(volumeInfo['maturityRating']),
      previewLink: _httpsUrl(_text(volumeInfo['previewLink'])),
      printType: _text(volumeInfo['printType']),
      isEbook: saleInfo['isEbook'] == true,
    );
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _httpsUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    return url.startsWith('http://')
        ? url.replaceFirst('http://', 'https://')
        : url;
  }
}
