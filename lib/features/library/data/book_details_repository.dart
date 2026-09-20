import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/book.dart';
import '../domain/book_edition.dart';
import '../domain/library_exception.dart';
import 'google_book.dart';
import 'supabase_guard.dart';

/// Reads and writes the book detail page's two caches — the extended info
/// columns on `books`, and the shared `book_editions` table — the same way
/// `BookCacheRepository` reads and writes `books` itself: plain selects to
/// read, and a `security definer` function as the only way to write,
/// because both caches are shared by every reader (see
/// `20260913110629_book_details_tags_comments.sql`).
///
/// Like `BookCacheRepository`, this knows nothing about *when* to go to
/// Google Books; that policy lives in `BookDetailsService`.
class BookDetailsRepository {
  BookDetailsRepository({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  /// The current `books` row for [bookId]. The detail page is opened with
  /// whatever `Book` the shelf loaded, which may predate a details fetch
  /// made on another device (or by another reader — the cache is shared);
  /// re-reading the row is what turns that into a cache hit.
  Future<Book?> fetchBook(String bookId) {
    return runSupabase(() async {
      final row = await _client
          .from('books')
          .select('*')
          .eq('id', bookId)
          .maybeSingle();
      return row == null ? null : Book.fromRow(row);
    }, friendlyMessage: "Couldn't load that book's details.");
  }

  /// Writes a fetched volume's extended info onto its existing cache row
  /// and returns the stored row, with `detailsFetchedAt` now set.
  /// [description] is passed separately because the caller has already
  /// turned Google's HTML into plain text.
  Future<Book> cacheDetails(GoogleBook volume, {String? description}) {
    return runSupabase(() async {
      final row = await _client.rpc<Map<String, dynamic>>(
        'cache_book_details',
        params: {
          'p_google_books_id': volume.id,
          'p_description': description,
          'p_subtitle': volume.subtitle,
          'p_publisher': volume.publisher,
          'p_published_date': volume.publishedDate,
          'p_categories': volume.categories,
          'p_language': volume.language,
          'p_isbn_10': volume.isbn10,
          'p_isbn_13': volume.isbn13,
          'p_average_rating': volume.averageRating,
          'p_ratings_count': volume.ratingsCount,
          'p_maturity_rating': volume.maturityRating,
          'p_preview_link': volume.previewLink,
          'p_page_count': volume.pageCount,
        },
      );
      return Book.fromRow(row);
    }, friendlyMessage: "Couldn't save that book's details.");
  }

  /// Every cached edition of [bookId], in display order. Returns an empty
  /// list for a book with none cached — callers decide whether that is a
  /// hit or a miss from `Book.editionsFetchedAt`, never from emptiness.
  Future<List<BookEdition>> fetchEditions(String bookId) {
    return runSupabase(() async {
      final rows = await _client
          .from('book_editions')
          .select()
          .eq('book_id', bookId);
      return [for (final row in rows) ?BookEdition.fromRow(row)];
    }, friendlyMessage: "Couldn't load that book's editions.");
  }

  /// Caches [editions] for [bookId] (upserting, so an edition a reader
  /// already owns keeps its id) and returns everything now cached for it.
  Future<List<BookEdition>> cacheEditions(
    String bookId,
    List<BookEdition> editions,
  ) {
    if (editions.length > 40) {
      throw const InvalidInputException('Too many editions.');
    }
    return runSupabase(() async {
      final rows = await _client.rpc<List<dynamic>>(
        'cache_book_editions',
        params: {
          'p_book_id': bookId,
          'p_editions': [for (final edition in editions) edition.toRpcJson()],
        },
      );
      return [
        for (final row in rows.whereType<Map<String, dynamic>>())
          ?BookEdition.fromRow(row),
      ];
    }, friendlyMessage: "Couldn't save that book's editions.");
  }
}
