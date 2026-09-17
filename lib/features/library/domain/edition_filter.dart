import '../data/google_book.dart';
import 'book.dart';
import 'book_edition.dart';

/// Turns a raw Google Books search for "this title by this author" into
/// the ebook and physical editions of *that* book — and nothing else.
///
/// Google's search is generous: a query for Dune also returns Dune
/// Messiah, study guides, "Summary of Dune", magazine issues that mention
/// it, and entries with no format information at all. Each rule below
/// removes one of those; what is left is shown on the detail page and
/// cached in `book_editions`.
///
/// Pure and synchronous, so the whole policy is unit-testable without a
/// network or a database.
abstract final class EditionFilter {
  /// Words that mark a volume as *about* the book rather than an edition
  /// *of* it, or as a format the page doesn't offer (audio).
  static const _excludedWords = [
    'summary',
    'study guide',
    'sparknotes',
    'cliffsnotes',
    'analysis',
    'workbook',
    'companion',
    'audiobook',
    'audio cd',
    'unabridged audio',
    'graphic novel',
    'boxed set',
    'box set',
    'collection',
  ];

  /// Most editions a single book will ever show — also the cap
  /// `cache_book_editions` enforces.
  static const maxEditions = 40;

  /// Filters [results] down to editions of [book], newest first within
  /// each format, ebooks before physical — the order the page lists them.
  static List<BookEdition> editionsOf(Book book, List<GoogleBook> results) {
    final wantedTitle = _mainTitle(book.title);
    // A title made entirely of punctuation normalizes to nothing, and
    // "nothing" would match every result — there is nothing to filter on.
    if (wantedTitle.isEmpty) return const [];
    final wantedAuthors = book.author == Book.unknownAuthor
        ? const <Set<String>>[]
        : [
            for (final name in book.author.split(',')) _authorTokens(name),
          ].where((tokens) => tokens.isNotEmpty).toList();
    final seen = <String>{};
    final editions = <BookEdition>[];

    for (final volume in results) {
      if (volume.id.isEmpty || !seen.add(volume.id)) continue;

      final format = formatOf(volume);
      if (format == null) continue;

      // Same book: the title before any colon/subtitle matches exactly
      // once punctuation and case are ignored. A prefix match would let
      // "Dune Messiah" through as an edition of "Dune".
      if (_mainTitle(volume.title) != wantedTitle) continue;

      // Same author, when both sides actually know one — see [_sameAuthor].
      if (wantedAuthors.isNotEmpty &&
          volume.authors.isNotEmpty &&
          !volume.authors.any(
            (name) => wantedAuthors.any(
              (wanted) => _sameAuthor(wanted, _authorTokens(name)),
            ),
          )) {
        continue;
      }

      final haystack = '${volume.title} ${volume.subtitle ?? ''}'.toLowerCase();
      if (_excludedWords.any(haystack.contains)) continue;

      editions.add(
        BookEdition(
          googleBooksId: volume.id,
          title: volume.title,
          subtitle: volume.subtitle,
          author: volume.authorLine,
          format: format,
          publisher: volume.publisher,
          publishedDate: volume.publishedDate,
          pageCount: volume.pageCount,
          language: volume.language,
          isbn13: volume.isbn13,
          isbn10: volume.isbn10,
          coverUrl: volume.thumbnailUrl,
        ),
      );
      if (editions.length == maxEditions) break;
    }

    editions.sort(compare);
    return editions;
  }

  /// Ebooks first, then physical; newest first within a format; then title
  /// so the order is stable for editions sharing a year.
  static int compare(BookEdition a, BookEdition b) {
    final byFormat = a.format.index.compareTo(b.format.index);
    if (byFormat != 0) return byFormat;
    final byDate = (b.publishedDate ?? '').compareTo(a.publishedDate ?? '');
    if (byDate != 0) return byDate;
    return a.title.compareTo(b.title);
  }

  /// The format of [volume], or null when it is neither an ebook nor a
  /// physical book (and so must not be offered):
  ///
  /// * anything whose `printType` isn't `BOOK` (magazines) — out;
  /// * `saleInfo.isEbook` — an ebook;
  /// * otherwise, an ISBN — a physical book. An ISBN is what a printed
  ///   book in a shop carries; a `BOOK` volume with neither sale nor ISBN
  ///   information is usually a scanned library copy with no format a
  ///   reader could own, so it is left out rather than guessed at.
  static EditionFormat? formatOf(GoogleBook volume) {
    final printType = volume.printType;
    if (printType != null && printType.toUpperCase() != 'BOOK') return null;
    if (volume.isEbook) return EditionFormat.ebook;
    if (volume.isbn13 != null || volume.isbn10 != null) {
      return EditionFormat.physical;
    }
    return null;
  }

  /// The Google Books query that finds editions of [book]: an `intitle:`
  /// on the main title plus an `inauthor:` on the author's last name when
  /// the author is known.
  static String queryFor(Book book) {
    final title = book.title.split(':').first.trim();
    final surname = book.author == Book.unknownAuthor
        ? null
        : book.author.split(',').first.trim().split(RegExp(r'\s+')).last;
    return [
      'intitle:"${title.replaceAll('"', '')}"',
      if (surname != null && surname.isNotEmpty)
        'inauthor:"${surname.replaceAll('"', '')}"',
    ].join(' ');
  }

  /// "Dune: Deluxe Edition" → "dune"; "The Hobbit, or There and Back
  /// Again" → "the hobbit".
  static String _mainTitle(String title) {
    final main = title.split(RegExp(r'[:;(]| - |, or ')).first;
    return main
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Whether two authors' name tokens describe the same person: one set
  /// contains the other. Google writes "Frank Herbert", "Herbert, Frank",
  /// "FRANK. HERBERT" and "F. Herbert" (initial dropped, so just
  /// {herbert}) for the same person, and all of those pass — but a shared
  /// surname alone does not, or Brian Herbert's "Dune: The Heir of Caladan"
  /// would count as an edition of Frank Herbert's "Dune".
  static bool _sameAuthor(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return false;
    return a.containsAll(b) || b.containsAll(a);
  }

  /// Name tokens long enough to mean something ("herbert", "frank"), so an
  /// initial like "F." doesn't count as a match on its own.
  static Set<String> _authorTokens(String author) {
    return author
        .toLowerCase()
        .split(RegExp(r'[^\p{L}]+', unicode: true))
        .where((token) => token.length > 2)
        .toSet();
  }
}

/// Google's volume endpoint returns the blurb as HTML (`<p>`, `<br>`,
/// `<i>`, `&amp;`). The app renders plain text, so tags become paragraph
/// breaks and entities are decoded — enough for what Google actually
/// sends, without pulling in an HTML parser for it.
String plainTextFromHtml(String html) {
  var text = html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>\s*', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n• ')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  const entities = {
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
    '&apos;': "'",
    '&nbsp;': ' ',
    '&mdash;': '—',
    '&ndash;': '–',
    '&hellip;': '…',
  };
  entities.forEach((entity, value) => text = text.replaceAll(entity, value));
  text = text.replaceAllMapped(
    RegExp(r'&#(x[0-9a-f]+|\d+);', caseSensitive: false),
    (match) {
      final digits = match.group(1)!;
      final hex = digits[0] == 'x' || digits[0] == 'X';
      final code = hex
          ? int.tryParse(digits.substring(1), radix: 16)
          : int.tryParse(digits);
      return code == null || code > 0x10FFFF ? '' : String.fromCharCode(code);
    },
  );
  return text
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
