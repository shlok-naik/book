import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/diagnostics/app_logger.dart';
import '../../../core/offline/pending_write.dart';
import '../domain/book.dart';
import '../domain/book_edition.dart';
import '../domain/library_book.dart';
import '../domain/library_exception.dart';
import '../domain/user_book.dart';
import 'offline_library_cache.dart';
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
///
/// ## Offline
///
/// With an [offline] cache injected (the app does; tests opt in), the shelf
/// keeps working without a connection:
///
/// * [fetchLibrary] caches every successful load, and answers from that
///   cache when the server can't be reached — or while writes made offline
///   are still waiting to sync, since the server's copy doesn't have them.
/// * Every write to an *existing* row — progress, shelf moves, the manual
///   order, ratings, restarts, owned editions, deletes — goes to the server
///   when it can. When it can't, the identical request is queued for
///   `SyncCoordinator` to replay, the cached row is patched to match, and
///   the caller gets that patched row back exactly as if the server had
///   answered. `LibraryController` can't tell the difference, which is the
///   point: its optimistic update simply never needs rolling back.
/// * Adding a *new* book ([start], [addWithStatus]) still needs the server
///   — it needs a cached catalogue row and a server-issued id — and fails
///   with the usual offline message.
///
/// Without [offline], every method behaves exactly as it always did.
class UserBookRepository {
  /// As in `BookCacheRepository`, the client is resolved lazily so the
  /// repository can exist before `Supabase.initialize` has run.
  UserBookRepository({SupabaseClient? client, this.offline})
    : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  /// The offline cache and write queue — see the class doc. Null means
  /// online-only.
  final OfflineLibraryCache? offline;

  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  static const _table = 'user_books';

  /// The embedded-join projection: every progress row plus the cached
  /// book it points at, in one round-trip instead of an N+1 fan-out.
  static const _withBook =
      '*, book:books(*), '
      // Named by foreign key: `book_editions` is reachable from here only
      // through the composite (book_id, owned_edition_id) key, and naming
      // it keeps PostgREST from guessing if another relationship appears.
      'owned_edition:book_editions!user_books_owned_edition_fkey(*)';

  /// Loads the whole shelf, most recently touched first.
  ///
  /// Rows whose joined book is missing (a cache row deleted out from
  /// under us) are skipped rather than failing the load — one orphan
  /// must not blank the entire library.
  Future<List<LibraryBook>> fetchLibrary() async {
    final offline = this.offline;
    if (offline != null && offline.isActive) {
      final pending = await offline.drainBeforeRead();
      if (pending || offline.shouldQueue) {
        final cached = await offline.readShelf();
        if (cached != null) return _parseShelf(cached);
      }
    }

    try {
      final rows = await runSupabase(
        () => _client
            .from(_table)
            .select(_withBook)
            .order('updated_at', ascending: false),
        friendlyMessage: "Couldn't load your library.",
      );
      await offline?.writeShelf(rows);
      return _parseShelf(rows);
    } on NetworkException {
      final cached = await offline?.readShelf();
      if (cached == null) rethrow;
      return _parseShelf(cached);
    }
  }

  /// Rows (fresh from the server, or cached) as the shelf, ordered like the
  /// query orders it. Parsed outside `runSupabase` so a cached shelf goes
  /// through the exact same code.
  List<LibraryBook> _parseShelf(List<Map<String, dynamic>> rows) {
    final ordered = [...rows]
      ..sort(
        (a, b) =>
            '${b['updated_at'] ?? ''}'.compareTo('${a['updated_at'] ?? ''}'),
      );
    final library = <LibraryBook>[];
    for (final row in ordered) {
      final bookRow = row['book'];
      if (bookRow is! Map<String, dynamic>) continue;
      final editionRow = row['owned_edition'];
      try {
        library.add(
          LibraryBook(
            book: Book.fromRow(bookRow),
            progress: UserBook.fromRow(row),
            // An unreadable edition row degrades to "no edition picked"
            // (the work's own cover and pages) rather than failing the
            // whole shelf.
            ownedEdition: editionRow is Map<String, dynamic>
                ? BookEdition.fromRow(editionRow)
                : null,
          ),
        );
      } on LibraryException catch (error) {
        // Same as the orphan rule above: one unreadable row must not
        // blank the whole library.
        AppLogger.warning(
          'UserBookRepository',
          'Skipped an unreadable shelf row.',
          error: error,
        );
      }
    }
    return library;
  }

  /// Writes [values] to the row [userBookId] and returns it — straight to
  /// the server when reachable, otherwise queued and applied to the cached
  /// row (see the class doc). A row that isn't cached can't be represented
  /// offline, so that case rethrows the network failure as it always did.
  ///
  /// [select] is the projection the server write returns; the cache keeps
  /// its embedded book either way.
  Future<UserBook> _updateRow(
    String userBookId,
    Map<String, Object?> values, {
    required String friendlyMessage,
    String select = '*',
  }) async {
    final offline = this.offline;
    if (offline != null && await offline.mustQueueWrite()) {
      final queued = await _queueUpdate(offline, userBookId, values);
      if (queued != null) {
        offline.syncSoon();
        return queued;
      }
      if (offline.shouldQueue) {
        // Known offline and nothing cached to patch: a request can only
        // time out, so say what's wrong now instead of in ten seconds.
        throw const NetworkException("You're offline.");
      }
      // Online with older writes still waiting, but this row isn't cached:
      // no queued update can name it either, so a direct write can't be
      // overtaken by one. Falls through to the server.
    }
    try {
      final row = await runSupabase(
        () => _client
            .from(_table)
            .update(values)
            .eq('id', userBookId)
            .select(select)
            .single(),
        friendlyMessage: friendlyMessage,
      );
      await offline?.mergeShelfRow(row);
      return UserBook.fromRow(row);
    } on NetworkException {
      if (offline == null || !offline.isActive) rethrow;
      final queued = await _queueUpdate(offline, userBookId, values);
      if (queued == null) rethrow;
      return queued;
    }
  }

  Future<UserBook?> _queueUpdate(
    OfflineLibraryCache offline,
    String userBookId,
    Map<String, Object?> values,
  ) async {
    final patched = await offline.patchShelfRow(userBookId, values);
    if (patched == null) return null;
    await offline.enqueue(
      PendingUpdate(
        id: offline.newWriteId(),
        createdAt: DateTime.now().toUtc(),
        table: _table,
        rowId: userBookId,
        values: values,
      ),
    );
    return UserBook.fromRow(patched);
  }

  /// Starts (or re-opens) a book at page 0.
  ///
  /// Never inserts a duplicate row for the same `book_id` — a second
  /// `start` finds the existing row instead — and deliberately never
  /// resets `current_page`, so a mistyped repeat can't wipe real
  /// progress. [StartOutcome.alreadyExists] tells the caller which case
  /// happened, so `LibraryController.startBook` can treat a repeat
  /// `start` as the no-op it is rather than reporting a fresh success.
  Future<StartOutcome> start(String bookId, {DateTime? startedAt}) {
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
            // A backdated `start Dune 2026-09-01` lands on the book page's
            // start date too, not just the reading event.
            'started_at': (startedAt ?? DateTime.now())
                .toUtc()
                .toIso8601String(),
          })
          // With the book embedded, so the offline cache holds a complete
          // row the moment the book lands — a reader who loses signal right
          // after starting it can still log progress against it.
          .select(_withBook)
          .single();
      await offline?.upsertShelfRow(row);
      return StartOutcome(UserBook.fromRow(row), alreadyExists: false);
    }, friendlyMessage: "Couldn't add that book to your library.");
  }

  /// Puts a book straight onto the shelf at [status] —
  /// `move <book> <shelf>` for a book not on the shelf yet — instead of the
  /// page-0 "reading" row [start] always creates. [shelfId] places it on a
  /// custom shelf the reader already made; it never creates one. [currentPage] is the
  /// page `ShelfRules.enter` decided the shelf implies (the last page for
  /// "finished", 0 otherwise). Same dedupe as [start]: a book already on
  /// the shelf in any status is found rather than duplicated, and the
  /// caller moves it with [changeShelf] instead.
  Future<StartOutcome> addWithStatus(
    String bookId,
    ReadingStatus status, {
    int currentPage = 0,
    String? shelfId,
    DateTime? startedAt,
    DateTime? finishedAt,
  }) {
    return runSupabase(() async {
      final existing = await _client
          .from(_table)
          .select()
          .eq('book_id', bookId)
          .maybeSingle();
      if (existing != null) {
        return StartOutcome(UserBook.fromRow(existing), alreadyExists: true);
      }

      final now = DateTime.now().toUtc().toIso8601String();
      final row = await _client
          .from(_table)
          .insert({
            'book_id': bookId,
            'current_page': currentPage < 0 ? 0 : currentPage,
            'status': status.wireValue,
            // `started_at` is not null with a now() default, so a queued
            // book gets one too; nothing reads it for a to-read book.
            'started_at': startedAt?.toUtc().toIso8601String() ?? now,
            if (status == ReadingStatus.finished)
              'finished_at': finishedAt?.toUtc().toIso8601String() ?? now,
            'shelf_id': ?shelfId,
          })
          .select(_withBook)
          .single();
      await offline?.upsertShelfRow(row);
      return StartOutcome(UserBook.fromRow(row), alreadyExists: false);
    }, friendlyMessage: "Couldn't add that book to your library.");
  }

  /// Persists a new page count, and the finished flag it may imply.
  ///
  /// The caller (the controller) is responsible for validating the page
  /// and deciding completion; this method only writes what it is told.
  ///
  /// [finishedAt], when given, backdates the finish instead of using
  /// the server clock — "I finished Dune yesterday" should leave the
  /// book's own record agreeing with the streak entry it produced.
  /// Ignored when [finished] is false: an in-progress book has no
  /// finish date to backdate.
  Future<UserBook> saveProgress({
    required String userBookId,
    required int currentPage,
    required bool finished,
    DateTime? finishedAt,
  }) {
    if (currentPage < 0) {
      throw const InvalidInputException("Page can't be negative.");
    }

    final at = (finishedAt ?? DateTime.now()).toUtc().toIso8601String();
    return _updateRow(userBookId, {
      'current_page': currentPage,
      'status': finished
          ? ReadingStatus.finished.wireValue
          : ReadingStatus.reading.wireValue,
      // Clearing finished_at when a finished book is re-opened keeps the
      // column honest.
      'finished_at': finished ? at : null,
      // `updated_at` is deliberately absent: a database trigger
      // (`user_books_touch_updated_at`) sets it from the server clock.
      // The shelf is ordered by that column, so letting the client
      // supply it let a device with a skewed clock pin its own rows to
      // the top or bottom of the ordering.
    }, friendlyMessage: "Couldn't save your progress.");
  }

  /// Moves an existing shelf row to [updated]'s shelf — its status and its
  /// custom shelf (`shelf_id`, null for a built-in shelf) — writing the
  /// progress that move implies, as `ShelfRules.enterShelf` computed it.
  /// Used by every section change: dragging a tile (or its keyboard/
  /// screen-reader equivalents) on the library page, and
  /// `move <book> <shelf>` on a book already on the shelf.
  ///
  /// `shelf_position` is not sent: the `touch_updated_at` trigger clears
  /// it on a status or shelf change, and a drop that also places the book
  /// follows up with [saveShelfOrder]. A `shelf_id` that isn't one of the
  /// reader's own shelves is refused by the composite foreign key.
  Future<UserBook> changeShelf(UserBook updated) {
    return _updateRow(updated.id, {
      'status': updated.status.wireValue,
      'current_page': updated.currentPage,
      'finished_at': updated.status == ReadingStatus.finished
          ? (updated.finishedAt ?? DateTime.now()).toUtc().toIso8601String()
          : null,
      'shelf_id': updated.shelfId,
      // `started_at` is not null in the schema, so it's only ever sent,
      // never cleared — [ShelfRules.enter] stamps it on a move into reading.
      if (updated.startedAt case final started?)
        'started_at': started.toUtc().toIso8601String(),
    }, friendlyMessage: "Couldn't move that book.");
  }

  /// Persists one shelf section's manual order: [orderedIds] become
  /// positions 0, 1, 2… in one round-trip (`set_shelf_order`). A
  /// position-only write deliberately leaves `updated_at` alone — see the
  /// trigger's comment in the migration — so reordering never changes
  /// which book the add tab calls "currently reading".
  Future<void> saveShelfOrder(List<String> orderedIds) async {
    if (orderedIds.isEmpty) return;
    final offline = this.offline;
    if (offline != null && await offline.mustQueueWrite()) {
      await _queueShelfOrder(offline, orderedIds);
      offline.syncSoon();
      return;
    }
    try {
      await runSupabase<void>(() async {
        await _client.rpc<void>(
          'set_shelf_order',
          params: {'p_ordered_ids': orderedIds},
        );
      }, friendlyMessage: "Couldn't save your shelf order.");
      await offline?.applyShelfOrder(orderedIds);
    } on NetworkException {
      if (offline == null || !offline.isActive) rethrow;
      await _queueShelfOrder(offline, orderedIds);
    }
  }

  Future<void> _queueShelfOrder(
    OfflineLibraryCache offline,
    List<String> orderedIds,
  ) async {
    await offline.applyShelfOrder(orderedIds);
    await offline.enqueue(
      PendingRpc(
        id: offline.newWriteId(),
        createdAt: DateTime.now().toUtc(),
        function: 'set_shelf_order',
        params: {'p_ordered_ids': orderedIds},
      ),
    );
  }

  /// Records which edition the reader owns, or clears it with null, and
  /// writes [currentPage] in the same update — switching to a copy with a
  /// different length rescales the page (see
  /// `ShelfRules.pageForEdition`), and the two must never be saved apart.
  /// The composite foreign key rejects an edition of a different book.
  Future<UserBook> setOwnedEdition(
    String userBookId,
    String? editionId, {
    required int currentPage,
  }) {
    if (currentPage < 0) {
      throw const InvalidInputException("Page can't be negative.");
    }
    return _updateRow(
      userBookId,
      {'owned_edition_id': editionId, 'current_page': currentPage},
      friendlyMessage: "Couldn't save which edition you own.",
      // The embedded edition changes with the id, so the cached row takes
      // the server's fresh embed rather than keeping a stale one.
      select: _withBook,
    );
  }

  /// The book page's start/finish date fields. [finishedAt] is written only
  /// for a finished book and must be null otherwise — the controller
  /// validates the pair (no future dates, no finish before the start)
  /// before this is ever called; this only guards the one rule the schema
  /// can't express on its own.
  Future<UserBook> saveDates(
    String userBookId, {
    required DateTime startedAt,
    DateTime? finishedAt,
  }) {
    if (finishedAt != null && finishedAt.isBefore(startedAt)) {
      throw const InvalidInputException('Finish is before start.');
    }
    return _updateRow(userBookId, {
      'started_at': startedAt.toUtc().toIso8601String(),
      'finished_at': ?finishedAt?.toUtc().toIso8601String(),
    }, friendlyMessage: "Couldn't save those dates.");
  }

  /// When the reader last imported a library — `profiles.library_imported_at`
  /// — or null if never (or the column isn't there yet). The stats page's
  /// pace baseline. A failure is reported as a [LibraryException] like any
  /// read; the controller treats it as "keep what was known".
  Future<DateTime?> fetchImportedAt() {
    return runSupabase(() async {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return null;
      final row = await _client
          .from('profiles')
          .select('library_imported_at')
          .eq('id', userId)
          .maybeSingle();
      final value = row?['library_imported_at'];
      return value is String ? DateTime.tryParse(value) : null;
    }, friendlyMessage: "Couldn't load your import date.");
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
      throw const InvalidInputException('Rate 0.5–5 stars.');
    }

    // As in `saveProgress`, `updated_at` is left to the database trigger
    // rather than sent from here.
    return _updateRow(userBookId, {
      'rating': rating,
    }, friendlyMessage: "Couldn't save that rating.");
  }

  /// Puts a finished book back on the reading shelf for another pass —
  /// `restart <book>`. Not routed through `saveProgress`/`changeShelf`:
  /// `reread_count` isn't a progress column either of those touches, so
  /// this is its own narrow update, the same shape as [rate].
  Future<UserBook> restart({
    required String userBookId,
    required int rereadCount,
  }) {
    return _updateRow(userBookId, {
      'current_page': 0,
      'status': ReadingStatus.reading.wireValue,
      'finished_at': null,
      'reread_count': rereadCount,
    }, friendlyMessage: "Couldn't restart that book.");
  }

  /// Removes a book from the shelf — `delete <book>`.
  ///
  /// Only deletes the `user_books` progress row, not the shared `books`
  /// cache entry: the cache exists so a re-`start` of the same title (or
  /// another lookup that happens to match the same volume) is still a
  /// hit instead of re-fetching from Google Books.
  Future<void> delete(String userBookId) async {
    final offline = this.offline;
    if (offline != null && await offline.mustQueueWrite()) {
      await _queueDelete(offline, userBookId);
      offline.syncSoon();
      return;
    }
    try {
      await runSupabase<void>(() async {
        await _client.from(_table).delete().eq('id', userBookId);
      }, friendlyMessage: "Couldn't remove that book.");
      await offline?.removeShelfRow(userBookId);
    } on NetworkException {
      if (offline == null || !offline.isActive) rethrow;
      await _queueDelete(offline, userBookId);
    }
  }

  Future<void> _queueDelete(
    OfflineLibraryCache offline,
    String userBookId,
  ) async {
    await offline.removeShelfRow(userBookId);
    await offline.enqueue(
      PendingDelete(
        id: offline.newWriteId(),
        createdAt: DateTime.now().toUtc(),
        table: _table,
        column: 'id',
        value: userBookId,
      ),
    );
  }
}
