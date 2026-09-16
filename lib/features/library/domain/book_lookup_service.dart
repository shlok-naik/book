import '../data/book_cache_repository.dart';
import '../data/google_book.dart';
import '../data/google_books_api_client.dart';
import '../data/open_library_client.dart';
import 'book.dart';
import 'library_exception.dart';

/// The single place that knows how a book is resolved from a title the
/// user typed. Every caller — the `start` command today, a search screen
/// tomorrow — goes through [findOrFetch] so the caching policy exists
/// once rather than being re-implemented per screen.
class BookLookupService {
  BookLookupService({
    required this.cache,
    required this.googleBooks,
    this.openLibrary,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Supabase-backed cache, checked before any network call.
  final BookCacheRepository cache;

  /// Fallback source, only reached on a cache miss.
  final GoogleBooksApiClient googleBooks;

  /// The backup when Google Books refuses — its keyless quota runs out every
  /// day — and the source of covers Google doesn't have. Null (tests, mostly)
  /// keeps Google Books the only source.
  final OpenLibraryClient? openLibrary;

  final DateTime Function() _clock;

  /// After Google fails once, it's skipped for [googleCooldown] and every
  /// search goes straight to Open Library — waiting on a quota that's spent
  /// is what made search slow.
  static const googleCooldown = Duration(minutes: 3);
  DateTime? _skipGoogleUntil;

  bool get _googleResting {
    final until = _skipGoogleUntil;
    return until != null && _clock().isBefore(until);
  }

  /// Google Books first, Open Library when Google is resting or fails with
  /// anything but "no such book". [newest] and [maxResults] carry over.
  Future<List<GoogleBook>> _searchVolumes(
    String query, {
    int maxResults = 10,
    String? orderBy,
  }) async {
    final backup = openLibrary;
    if (backup != null && _googleResting) {
      return backup.search(
        query,
        limit: maxResults,
        newest: orderBy == 'newest',
      );
    }
    try {
      return await googleBooks.search(
        query,
        maxResults: maxResults,
        orderBy: orderBy,
      );
    } on LibraryException catch (error) {
      if (backup == null ||
          error is InvalidInputException ||
          error is BookNotFoundException) {
        rethrow;
      }
      _skipGoogleUntil = _clock().add(googleCooldown);
      return backup.search(
        query,
        limit: maxResults,
        newest: orderBy == 'newest',
      );
    }
  }

  /// [volume], with an Open Library cover when Google had none — so the
  /// cover cached for every reader is a real one.
  Future<GoogleBook> _withCover(GoogleBook volume) async {
    final backup = openLibrary;
    if (backup == null || _hasCover(volume)) return volume;
    final url = await backup.coverFor(
      isbn: volume.isbn13 ?? volume.isbn10,
      title: volume.title,
      author: volume.authors.firstOrNull,
    );
    return url == null ? volume : volume.withThumbnail(url);
  }

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
      throw const InvalidInputException('Enter a title.');
    }
    if (query.length > maxQueryLength) {
      throw const InvalidInputException('Title too long.');
    }

    // ---- 2. Cache first ---------------------------------------------
    final cached = await _findCached(query, author: author);
    if (cached != null) return cached;

    // ---- 3. Cache miss: go to Google Books ---------------------------
    final results = await _searchVolumes(
      author == null || author.isEmpty ? query : '$query $author',
    );
    if (results.isEmpty) {
      throw BookNotFoundException('Nothing found for "$query".');
    }
    final volume = _bestMatch(results, query);

    // ---- 4. De-duplicate on the Google id ----------------------------
    final alreadyCached = await _findCachedById(volume.id);
    if (alreadyCached != null) return alreadyCached;

    // ---- 5. Write back so the next lookup is a cache hit -------------
    return cache.cache(await _withCover(volume));
  }

  /// Resolves an ISBN to a cached [Book] — the import's first choice, since
  /// an ISBN names one book where a title can name several. Cache first,
  /// then Google Books' `isbn:` search, then the same de-duplicate and
  /// write-back as [findOrFetch]. Throws [BookNotFoundException] when Google
  /// has nothing for it.
  Future<Book> findOrFetchByIsbn(String isbn) async {
    final clean = isbn.replaceAll(RegExp('[^0-9Xx]'), '').toUpperCase();
    if (clean.length != 10 && clean.length != 13) {
      throw const InvalidInputException("That isn't an ISBN.");
    }

    try {
      final cached = await cache.findByIsbn(clean);
      if (cached != null) return cached;
    } on LibraryException {
      // Degrades to a miss, like every other cache read.
    }

    final results = await _searchVolumes('isbn:$clean', maxResults: 5);
    if (results.isEmpty) {
      throw BookNotFoundException('No book for ISBN $clean.');
    }
    final volume = results.first;
    final alreadyCached = await _findCachedById(volume.id);
    if (alreadyCached != null) return alreadyCached;
    return cache.cache(await _withCover(volume));
  }

  /// Every Google Books volume matching [rawQuery], in Google's order —
  /// the search tab's results and the book picker's catalogue tab. Nothing
  /// is cached until the reader picks one ([resolveVolume]).
  ///
  /// Same validation and errors as [findOrFetch], except no results is an
  /// empty list rather than a [BookNotFoundException].
  Future<List<GoogleBook>> searchCatalogue(
    String rawQuery, {
    int maxResults = 20,
    String? orderBy,
  }) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      throw const InvalidInputException('Enter a title.');
    }
    if (query.length > maxQueryLength) {
      throw const InvalidInputException('Search too long.');
    }
    return _searchVolumes(query, maxResults: maxResults, orderBy: orderBy);
  }

  /// The cached [Book] for a volume the reader picked from [searchCatalogue]
  /// — the existing row when this volume was cached before, otherwise
  /// written now. Same de-duplicate and write-back as [findOrFetch].
  Future<Book> resolveVolume(GoogleBook volume) async {
    final cached = await _findCachedById(volume.id);
    if (cached != null) return cached;
    return cache.cache(await _withCover(volume));
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
  ///
  /// Within each of those tiers, a volume *with a cover* wins over one
  /// without: Google often lists a coverless record (a bare ISBN entry)
  /// ahead of the same book with its jacket, and whichever is picked here
  /// is what every reader of that book sees on their shelf.
  GoogleBook _bestMatch(List<GoogleBook> results, String query) {
    final needle = query.toLowerCase();
    final tiers = <bool Function(GoogleBook)>[
      (book) => book.title.toLowerCase() == needle,
      (book) => book.title.toLowerCase().startsWith(needle),
      (_) => true,
    ];
    for (final inTier in tiers) {
      final matches = results.where(inTier);
      if (matches.isEmpty) continue;
      return matches.where(_hasCover).firstOrNull ?? matches.first;
    }
    return results.first;
  }

  static bool _hasCover(GoogleBook book) {
    final url = book.thumbnailUrl;
    return url != null && url.isNotEmpty;
  }
}
