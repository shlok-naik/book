import '../data/book_cache_repository.dart';
import '../data/google_book.dart';
import '../data/google_books_api_client.dart';
import 'book.dart';
import 'library_exception.dart';

/// The single place that knows how a book is resolved from a title the
/// user typed. Every caller — the `start` command today, a search screen
/// tomorrow — goes through [findOrFetch] so the caching policy exists
/// once rather than being re-implemented per screen.
class BookLookupService {
  BookLookupService({required this.cache, required this.googleBooks});

  /// Supabase-backed cache, checked before any network call.
  final BookCacheRepository cache;

  /// Fallback source, only reached on a cache miss.
  final GoogleBooksApiClient googleBooks;

  /// Longest query we'll accept. Google Books ignores anything past a
  /// few hundred characters anyway, and it keeps a pasted paragraph from
  /// becoming a request URL.
  static const maxQueryLength = 200;

  /// Resolves [rawQuery] to a cached [Book], cache-first.
  ///
  /// The strategy, in order:
  ///   1. Validate the query (non-empty, not absurdly long). Nothing
  ///      touches the network for input we already know is unusable.
  ///   2. Ask Supabase. A hit returns immediately and Google Books is
  ///      never called — this is the whole point of the cache.
  ///   3. On a miss, search Google Books.
  ///   4. Re-check the cache by the winning volume's Google id: the
  ///      title the user typed may not match how the book is stored
  ///      ("dune messiah" vs "Dune Messiah: Book Two"), and without this
  ///      step we'd write a duplicate row on every alternate spelling.
  ///   5. Write the volume back to Supabase and return the stored row,
  ///      so the next lookup for this book stops at step 2.
  ///
  /// Error paths, all surfaced as [LibraryException] subtypes the UI can
  /// render directly:
  ///   * [InvalidInputException] — empty/oversized query (step 1).
  ///   * [BookNotFoundException] — Google Books answered with zero
  ///     results (step 3). This is a normal outcome, not a fault.
  ///   * [NetworkException] — offline, timeout, or a 5xx from either
  ///     service. Retrying may work.
  ///   * [RemoteDataException] — an unparseable response, or a rejected
  ///     cache write. Retrying will not help.
  ///
  /// One asymmetry is deliberate: a *read* failure against Supabase
  /// (step 2) is swallowed and treated as a cache miss, because Google
  /// Books can still answer and the user gets their book. A *write*
  /// failure (step 5) is not swallowed — the Supabase row id is what
  /// reading progress hangs off, so without it there is nothing to
  /// start.
  Future<Book> findOrFetch(String rawQuery, {String? author}) async {
    // ---- 1. Validate ------------------------------------------------
    final query = rawQuery.trim();
    if (query.isEmpty) {
      throw const InvalidInputException('Enter a book title first.');
    }
    if (query.length > maxQueryLength) {
      throw const InvalidInputException(
        'That title is too long — try just the book name.',
      );
    }

    // ---- 2. Cache first ---------------------------------------------
    final cached = await _findCached(query, author: author);
    if (cached != null) return cached;

    // ---- 3. Cache miss: go to Google Books ---------------------------
    final results = await googleBooks.search(
      author == null || author.isEmpty ? query : '$query $author',
    );
    if (results.isEmpty) {
      throw BookNotFoundException('No books found for "$query".');
    }
    final volume = _bestMatch(results, query);

    // ---- 4. De-duplicate on the Google id ----------------------------
    final alreadyCached = await _findCachedById(volume.id);
    if (alreadyCached != null) return alreadyCached;

    // ---- 5. Write back so the next lookup is a cache hit -------------
    return cache.cache(volume);
  }

  /// Cache read that degrades to a miss. A cache that is down must slow
  /// the flow, not break it — see the asymmetry note on [findOrFetch].
  Future<Book?> _findCached(String query, {String? author}) async {
    try {
      return await cache.findByTitle(query, author: author);
    } on LibraryException {
      return null;
    }
  }

  Future<Book?> _findCachedById(String googleBooksId) async {
    try {
      return await cache.findByGoogleBooksId(googleBooksId);
    } on LibraryException {
      return null;
    }
  }

  /// Google Books orders by its own relevance, which is usually right
  /// but happily puts a study guide above the novel. Prefer an exact
  /// case-insensitive title match, then a title that starts with the
  /// query, then fall back to the API's own first choice.
  GoogleBook _bestMatch(List<GoogleBook> results, String query) {
    final needle = query.toLowerCase();

    for (final book in results) {
      if (book.title.toLowerCase() == needle) return book;
    }
    for (final book in results) {
      if (book.title.toLowerCase().startsWith(needle)) return book;
    }
    return results.first;
  }
}
