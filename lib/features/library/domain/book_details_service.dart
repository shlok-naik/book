import '../../../core/diagnostics/app_logger.dart';
import '../data/book_details_repository.dart';
import '../data/google_books_api_client.dart';
import 'book.dart';
import 'book_edition.dart';
import 'edition_filter.dart';
import 'library_exception.dart';

/// The one place that decides how the book detail page's extra info and
/// editions are resolved — the detail-page counterpart of
/// `BookLookupService`, with the same cache-first policy:
///
///   1. Ask Supabase. A hit returns without touching Google Books.
///   2. On a miss, ask Google Books.
///   3. Write the answer back to Supabase, so the next reader (on any
///      device) stops at step 1.
///
/// "Hit" is decided by a `*_fetched_at` stamp on the `books` row, never by
/// whether data came back: a book Google has no editions for is cached as
/// *known to have none*, not re-queried on every visit.
///
/// And the same read/write asymmetry `BookLookupService` documents: a
/// failed cache *read* is logged and treated as a miss (Google Books can
/// still answer), because a cache that is down must slow the page, not
/// break it.
class BookDetailsService {
  BookDetailsService({required this.cache, required this.googleBooks});

  final BookDetailsRepository cache;
  final GoogleBooksApiClient googleBooks;

  /// Maximum volumes asked for when searching for editions — Google's cap.
  static const _editionSearchSize = 40;

  /// [book] with its extended info filled in.
  ///
  /// A failed cache *write* after a successful fetch still returns the
  /// fetched info: unlike editions, nothing here needs a database id to be
  /// useful, so the reader gets the page and the next visit simply tries
  /// the write again.
  ///
  /// Throws [LibraryException] only when neither the cache nor Google
  /// Books could answer — and callers can still render [book] itself.
  Future<Book> detailsFor(Book book) async {
    if (book.hasCachedDetails) return book;

    final cached = await _readCache(() => cache.fetchBook(book.id));
    if (cached != null && cached.hasCachedDetails) return cached;

    final volume = await googleBooks.fetchVolume(book.googleBooksId);
    final rawDescription = volume.description;
    final description = rawDescription == null
        ? null
        : plainTextFromHtml(rawDescription);

    try {
      return await cache.cacheDetails(volume, description: description);
    } on LibraryException catch (error) {
      AppLogger.error(
        'BookDetailsService',
        'Fetched book details but could not cache them.',
        error: error,
      );
      return Book(
        id: book.id,
        googleBooksId: book.googleBooksId,
        title: book.title,
        author: book.author,
        coverUrl: book.coverUrl ?? volume.thumbnailUrl,
        // The cached count wins, as in `cache_book_details`: progress
        // percentages hang off it, and the volume may be another printing.
        pageCount: book.pageCount ?? volume.pageCount,
        description: (description == null || description.isEmpty)
            ? book.description
            : description,
        subtitle: volume.subtitle,
        publisher: volume.publisher,
        publishedDate: volume.publishedDate,
        categories: volume.categories,
        language: volume.language,
        isbn10: volume.isbn10,
        isbn13: volume.isbn13,
        averageRating: volume.averageRating,
        ratingsCount: volume.ratingsCount,
        maturityRating: volume.maturityRating,
        previewLink: volume.previewLink,
        // Deliberately left null: the write failed, so this is not cached.
      );
    }
  }

  /// The ebook and physical editions of [book], cached ids included.
  ///
  /// Unlike [detailsFor], a failed cache write *is* an error here: an
  /// edition without a `book_editions` id can't be marked as owned, and a
  /// list of editions the reader can't select from is the one thing this
  /// section exists to avoid. The page shows the error with a retry.
  Future<List<BookEdition>> editionsFor(Book book) async {
    if (book.hasCachedEditions) {
      final cached = await _readCache(() => cache.fetchEditions(book.id));
      if (cached != null) return _sorted(cached);
    } else {
      // The shelf's copy of the row may be stale — another reader (or this
      // one, on another device) may already have filled the cache.
      final fresh = await _readCache(() => cache.fetchBook(book.id));
      if (fresh != null && fresh.hasCachedEditions) {
        final cached = await _readCache(() => cache.fetchEditions(book.id));
        if (cached != null) return _sorted(cached);
      }
    }

    final results = await googleBooks.search(
      EditionFilter.queryFor(book),
      maxResults: _editionSearchSize,
    );
    final editions = EditionFilter.editionsOf(book, results);
    final stored = await cache.cacheEditions(book.id, editions);
    return _sorted(stored);
  }

  List<BookEdition> _sorted(List<BookEdition> editions) =>
      [...editions]..sort(EditionFilter.compare);

  Future<T?> _readCache<T>(Future<T?> Function() read) async {
    try {
      return await read();
    } on LibraryException catch (error) {
      AppLogger.info(
        'BookDetailsService',
        'Cache read failed; falling back to Google Books ($error).',
      );
      return null;
    }
  }
}
