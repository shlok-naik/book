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

    return runSupabase(
      () async {
        final row = await _client
            .from(_table)
            .select()
            .eq('google_books_id', googleBooksId.trim())
            .maybeSingle();
        return row == null ? null : Book.fromRow(row);
      },
      friendlyMessage: "We couldn't check your saved books.",
    );
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

    return runSupabase(
      () async {
        final exact = await _selectFirst(
          titlePattern: escapeLikePattern(trimmedTitle),
          author: author,
        );
        if (exact != null) return exact;

        return _selectFirst(
          titlePattern: '${escapeLikePattern(trimmedTitle)}%',
          author: author,
        );
      },
      friendlyMessage: "We couldn't check your saved books.",
    );
  }

  Future<Book?> _selectFirst({
    required String titlePattern,
    String? author,
  }) async {
    var query = _client.from(_table).select().ilike('title', titlePattern);
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
  /// Upserts on `google_books_id` so a concurrent write — two "start"
  /// commands for the same book racing — resolves to one row instead of
  /// raising a unique-constraint error.
  Future<Book> cache(GoogleBook volume) {
    if (volume.id.trim().isEmpty) {
      throw const RemoteDataException(
        "We couldn't save that book to your library.",
        cause: 'Google Books volume has no id; nothing to de-duplicate on.',
      );
    }

    return runSupabase(
      () async {
        final row = await _client
            .from(_table)
            .upsert({
              'google_books_id': volume.id.trim(),
              'title': volume.title,
              'author': volume.authorLine,
              'cover_url': volume.thumbnailUrl,
              'page_count': volume.pageCount,
              'description': volume.description,
            }, onConflict: 'google_books_id')
            .select()
            .single();
        return Book.fromRow(row);
      },
      friendlyMessage: "We couldn't save that book to your library.",
    );
  }
}
