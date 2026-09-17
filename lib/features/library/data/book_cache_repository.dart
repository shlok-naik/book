import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/book.dart';
import '../domain/library_exception.dart';
import 'google_book.dart';
import 'supabase_guard.dart';

/// Reads and writes the Supabase `books` table — the shared cache of
/// Google Books volumes (see `supabase/schema.sql`).
///
/// This type knows nothing about *why* a lookup happens; the cache-first
/// policy lives in `BookLookupService`. Here we only do the four things
/// that policy needs: look up by Google id, look up by title/author, and
/// write a fetched volume back.
class BookCacheRepository {
  /// The client is resolved lazily rather than captured in the
  /// constructor so a repository can be built before (or without)
  /// `Supabase.initialize` — widget tests construct the app without it.
  BookCacheRepository({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  static const _table = 'books';

  /// Cache lookup on the de-duplication key. Returns null on a miss.
  Future<Book?> findByGoogleBooksId(String googleBooksId) {
    if (googleBooksId.trim().isEmpty) return Future.value(null);

    return runSupabase(() async {
      final row = await _client
          .from(_table)
          .select('*')
          .eq('google_books_id', googleBooksId.trim())
          .maybeSingle();
      return row == null ? null : Book.fromRow(row);
    }, friendlyMessage: "Couldn't check your saved books.");
  }

  /// Cache lookup by ISBN-13 or ISBN-10 — both columns are filled in once a
  /// book's details have been fetched. Returns null on a miss.
  Future<Book?> findByIsbn(String isbn) {
    // Only digits and a check-digit X: the value is spliced into a
    // PostgREST `or` filter, where a comma or parenthesis would add terms.
    final clean = isbn.replaceAll(RegExp('[^0-9Xx]'), '').toUpperCase();
    if (clean.length != 10 && clean.length != 13) return Future.value(null);
    return runSupabase(() async {
      final rows = await _client
          .from(_table)
          .select('*')
          .or('isbn_13.eq.$clean,isbn_10.eq.$clean')
          .limit(1);
      return rows.isEmpty ? null : Book.fromRow(rows.first);
    }, friendlyMessage: "Couldn't check your saved books.");
  }

  /// Cache lookup by what the user actually typed.
  ///
  /// Matches the title case-insensitively and exactly first (a reader
  /// typing "dune" means the book called "Dune", not "Dune Messiah");
  /// only if that misses does it try a prefix match, so `start dune` can
  /// still hit a cached "Dune: Deluxe Edition". [author], when given,
  /// further narrows the match — needed for distinct books that share a
  /// title. Returns null on a miss.
  Future<Book?> findByTitle(String title, {String? author}) {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) return Future.value(null);

    return runSupabase(() async {
      final exact = await _selectFirst(
        titlePattern: escapeLikePattern(trimmedTitle),
        author: author,
      );
      if (exact != null) return exact;

      return _selectFirst(
        titlePattern: '${escapeLikePattern(trimmedTitle)}%',
        author: author,
      );
    }, friendlyMessage: "Couldn't check your saved books.");
  }

  Future<Book?> _selectFirst({
    required String titlePattern,
    String? author,
  }) async {
    var query = _client.from(_table).select('*').ilike('title', titlePattern);
    if (author != null && author.trim().isNotEmpty) {
      query = query.ilike('author', '%${escapeLikePattern(author.trim())}%');
    }

    // limit(1) rather than single(): duplicate titles are legitimate
    // (different editions), and a second row must not fail the lookup.
    final rows = await query.limit(1);
    if (rows.isEmpty) return null;
    return Book.fromRow(rows.first);
  }

  /// Writes a Google Books volume into the cache and returns the stored
  /// row (we need Supabase's generated `id` to hang progress off).
  ///
  /// Goes through the `cache_book` database function rather than a
  /// direct upsert, because `books` is not client-writable: it is a
  /// cache *shared* by every reader, so a table-level insert/update
  /// grant would also let any one of them rewrite or delete rows out
  /// from under everyone else. The function upserts on
  /// `google_books_id` — so a concurrent write (two "start" commands
  /// for the same book racing) resolves to one row rather than raising
  /// a unique-constraint error — and can do nothing else.
  Future<Book> cache(GoogleBook volume) {
    if (volume.id.trim().isEmpty) {
      throw const RemoteDataException(
        "Couldn't save book.",
        cause: 'Google Books volume has no id; nothing to de-duplicate on.',
      );
    }

    return runSupabase(() async {
      final row = await _client.rpc<Map<String, dynamic>>(
        'cache_book',
        params: {
          'p_google_books_id': volume.id.trim(),
          'p_title': volume.title,
          'p_author': volume.authorLine,
          'p_cover_url': volume.thumbnailUrl,
          'p_page_count': volume.pageCount,
          'p_description': volume.description,
          'p_categories': volume.categories,
        },
      );
      return Book.fromRow(row);
    }, friendlyMessage: "Couldn't save that book to your library.");
  }
}
