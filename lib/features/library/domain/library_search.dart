import 'library_book.dart';

/// Matching for the library page's search field.
///
/// A book matches when every word of the query appears somewhere in its
/// title, subtitle, author, series name or the reader's own tags — so
/// "herbert dune" finds Dune, and "sci-fi 2" doesn't need the words in
/// order. Case-insensitive, and accents are ignored ("tolkien" finds
/// "Tolkíen").
abstract final class LibrarySearch {
  static bool matches(
    LibraryBook entry,
    String query, {
    Iterable<String> tags = const [],
  }) {
    final words = normalize(query).split(' ').where((w) => w.isNotEmpty);
    if (words.isEmpty) return true;
    final book = entry.book;
    final haystack = normalize(
      [
        book.title,
        ?book.subtitle,
        book.author,
        ?book.seriesName,
        ...tags,
      ].join(' | '),
    );
    return words.every(haystack.contains);
  }

  static String normalize(String text) =>
      _stripAccents(text.toLowerCase()).replaceAll(RegExp(r'\s+'), ' ').trim();

  static const _accents = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', //
    'ç': 'c',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', //
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', //
    'ñ': 'n',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', //
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', //
    'ý': 'y', 'ÿ': 'y',
  };

  static String _stripAccents(String text) {
    final buffer = StringBuffer();
    for (final char in text.split('')) {
      buffer.write(_accents[char] ?? char);
    }
    return buffer.toString();
  }
}
