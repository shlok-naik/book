import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/book.dart';
import '../domain/library_book.dart';
import '../domain/library_exception.dart';
import '../domain/user_book.dart';
import 'supabase_guard.dart';

/// Result of [UserBookRepository.start]: the shelf row, and whether it
/// already existed before this call.
class StartOutcome {
  const StartOutcome(this.progress, {required this.alreadyExists});

  final UserBook progress;
  final bool alreadyExists;
}

/// Reads and writes the Supabase `user_books` table — the reader's
/// progress rows (see `supabase/schema.sql`).
///
/// Authentication is out of scope, so every row here belongs to the one
/// local reader; adding a `user_id` filter later is the only change this
/// class would need.
class UserBookRepository {
  /// As in `BookCacheRepository`, the client is resolved lazily so the
  /// repository can exist before `Supabase.initialize` has run.
  UserBookRepository({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  static const _table = 'user_books';

  /// The embedded-join projection: every progress row plus the cached
  /// book it points at, in one round-trip instead of an N+1 fan-out.
  static const _withBook = '*, book:books(*)';

  /// Loads the whole shelf, most recently touched first.
  ///
  /// Rows whose joined book is missing (a cache row deleted out from
  /// under us) are skipped rather than failing the load — one orphan
  /// must not blank the entire library.
  Future<List<LibraryBook>> fetchLibrary() {
    return runSupabase(() async {
      final rows = await _client
          .from(_table)
          .select(_withBook)
          .order('updated_at', ascending: false);

      final library = <LibraryBook>[];
      for (final row in rows) {
        final bookRow = row['book'];
        if (bookRow is! Map<String, dynamic>) continue;
        library.add(
          LibraryBook(
            book: Book.fromRow(bookRow),
            progress: UserBook.fromRow(row),
          ),
        );
      }
      return library;
    }, friendlyMessage: "We couldn't load your library.");
  }

  /// Starts (or re-opens) a book at page 0.
  ///
  /// Never inserts a duplicate row for the same `book_id` — a second
  /// `start` finds the existing row instead — and deliberately never
  /// resets `current_page`, so a mistyped repeat can't wipe real
  /// progress. [StartOutcome.alreadyExists] tells the caller which case
  /// happened, so `LibraryController.startBook` can treat a repeat
  /// `start` as the no-op it is rather than reporting a fresh success.
  Future<StartOutcome> start(String bookId) {
    return runSupabase(() async {
      final existing = await _client
          .from(_table)
          .select()
          .eq('book_id', bookId)
          .maybeSingle();
      if (existing != null) {
        return StartOutcome(UserBook.fromRow(existing), alreadyExists: true);
      }

      final row = await _client
          .from(_table)
          .insert({
            'book_id': bookId,
            'current_page': 0,
            'status': ReadingStatus.reading.wireValue,
            'started_at': DateTime.now().toUtc().toIso8601String(),
          })
          .select()
          .single();
      return StartOutcome(UserBook.fromRow(row), alreadyExists: false);
    }, friendlyMessage: "We couldn't add that book to your library.");
  }

  /// Persists a new page count, and the finished flag it may imply.
  ///
  /// The caller (the controller) is responsible for validating the page
  /// and deciding completion; this method only writes what it is told.
  Future<UserBook> saveProgress({
    required String userBookId,
    required int currentPage,
    required bool finished,
  }) {
    if (currentPage < 0) {
      throw const InvalidInputException("A page number can't be negative.");
    }

    return runSupabase(() async {
      final now = DateTime.now().toUtc().toIso8601String();
      final row = await _client
          .from(_table)
          .update({
            'current_page': currentPage,
            'status': finished
                ? ReadingStatus.finished.wireValue
                : ReadingStatus.reading.wireValue,
            // Clearing finished_at when a finished book is re-opened
            // keeps the column honest.
            'finished_at': finished ? now : null,
            // `updated_at` is deliberately absent: a database trigger
            // (`user_books_touch_updated_at`) sets it from the server
            // clock. The shelf is ordered by that column, so letting
            // the client supply it let a device with a skewed clock
            // pin its own rows to the top or bottom of the ordering.
          })
          .eq('id', userBookId)
          .select()
          .single();
      return UserBook.fromRow(row);
    }, friendlyMessage: "We couldn't save your progress.");
  }

  /// Persists a rating — `rate <book> <stars>`.
  ///
  /// Whether the book is actually finished is
  /// `LibraryController.rateBook`'s call, not this method's; it only
  /// range-checks the number itself (the same 0-exclusive-to-5 range the
  /// `rating` column's check constraint enforces) so a bad value fails
  /// fast instead of round-tripping to Supabase first.
  Future<UserBook> rate({required String userBookId, required double rating}) {
    if (rating <= 0 || rating > 5) {
      throw const InvalidInputException('Ratings are between 0.5 and 5 stars.');
    }

    return runSupabase(() async {
      final row = await _client
          .from(_table)
          // As in `updateProgress`, `updated_at` is left to the
          // database trigger rather than sent from here.
          .update({'rating': rating})
          .eq('id', userBookId)
          .select()
          .single();
      return UserBook.fromRow(row);
    }, friendlyMessage: "We couldn't save that rating.");
  }

  /// Removes a book from the shelf — `delete <book>`.
  ///
  /// Only deletes the `user_books` progress row, not the shared `books`
  /// cache entry: the cache exists so a re-`start` of the same title (or
  /// another lookup that happens to match the same volume) is still a
  /// hit instead of re-fetching from Google Books.
  Future<void> delete(String userBookId) {
    return runSupabase<void>(() async {
      await _client.from(_table).delete().eq('id', userBookId);
    }, friendlyMessage: "We couldn't remove that book.");
  }
}
