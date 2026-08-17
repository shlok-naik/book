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
  });

  final String id;
  final String title;
  final List<String> authors;
  final String? thumbnailUrl;
  final String? description;

  /// Total pages, when the volume reports it. Needed to turn a logged
  /// page number into a completion percentage.
  final int? pageCount;

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
    );
  }

  static String? _httpsUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    return url.startsWith('http://')
        ? url.replaceFirst('http://', 'https://')
        : url;
  }
}
