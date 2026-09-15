import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/pending_write.dart';
import '../domain/library_exception.dart';
import '../domain/reading_event.dart';
import 'offline_library_cache.dart';
import 'supabase_guard.dart';

/// Reads and writes the Supabase `reading_events` table — one row per
/// shelf command that actually took effect (see `supabase/schema.sql`),
/// which the streaks page groups by day to decide what to draw.
///
/// Like `UserBookRepository`, every row belongs to the one signed-in
/// reader; `user_id` is never set by the app itself, RLS and the column
/// default handle it.
///
/// With an [offline] cache injected, the journal keeps working without a
/// connection the same way the shelf does (see `UserBookRepository`): a
/// logged event is queued and added to the cached year, a fetch answers
/// from that cache, and a title's history can be cleared offline too.
class ReadingEventRepository {
  ReadingEventRepository({SupabaseClient? client, this.offline})
    : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  /// Null means online-only.
  final OfflineLibraryCache? offline;

  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  static const _table = 'reading_events';

  /// Records that [type] happened, against [title] — carried along
  /// purely so the journal page can list "started Dune" rather than
  /// just "started". Fire-and-forget from the caller's side — a failed
  /// log must never surface as a failed shelf command, so callers wrap
  /// this in `unawaited(...catchError(...))` rather than awaiting it
  /// inline.
  ///
  /// [occurredAt], when given, backdates the row instead of leaving it
  /// to the column's own `now()` default — "I started Dune yesterday"
  /// logs (and streaks) on that day rather than the day the command was
  /// actually typed. `LibraryController` is responsible for rejecting a
  /// future date before it ever reaches here.
  ///
  /// [value] is the page an `update` reached or the rating a `rate`
  /// gave — whatever number the journal line needs to read "up to page
  /// 240" or "4.5 stars" instead of just naming the command. Left out
  /// for every other type.
  Future<void> log(
    ReadingEventType type, {
    required String title,
    DateTime? occurredAt,
    double? value,
  }) async {
    final values = <String, Object?>{
      'action': type.wireValue,
      'title': title,
      if (occurredAt != null)
        'occurred_at': occurredAt.toUtc().toIso8601String(),
      'value': ?value,
    };
    final offline = this.offline;
    if (offline != null && await offline.mustQueueWrite()) {
      await _queueLog(offline, values);
      offline.syncSoon();
      return;
    }
    try {
      await runSupabase<void>(() async {
        await _client.from(_table).insert(values);
      }, friendlyMessage: "We couldn't record that.");
      // Kept in the cached year too, so the journal still has it if the
      // connection drops before the next full fetch.
      await offline?.appendEvent(_localRow(values));
    } on NetworkException {
      if (offline == null || !offline.isActive) rethrow;
      await _queueLog(offline, values);
    }
  }

  Future<void> _queueLog(
    OfflineLibraryCache offline,
    Map<String, Object?> values,
  ) async {
    // An offline event must carry its own time: replayed later without
    // one, the column default would stamp it with the moment it synced.
    final stamped = {
      ...values,
      'occurred_at':
          values['occurred_at'] ?? DateTime.now().toUtc().toIso8601String(),
    };
    await offline.appendEvent(_localRow(stamped));
    await offline.enqueue(
      PendingInsert(
        id: offline.newWriteId(),
        createdAt: DateTime.now().toUtc(),
        table: _table,
        values: stamped,
      ),
    );
  }

  static Map<String, dynamic> _localRow(Map<String, Object?> values) => {
    ...values,
    'occurred_at':
        values['occurred_at'] ?? DateTime.now().toUtc().toIso8601String(),
  };

  /// Every event in [year], oldest first — enough for the streaks page
  /// to group into days and pick a symbol for each.
  ///
  /// The query window is [year]'s boundaries in *local* time, converted
  /// to UTC — matching how the streaks page groups rows back by local
  /// day. Querying a plain UTC year here would clip or leak boundary
  /// events for any reader not on UTC (e.g. a late Dec 31 local event
  /// with a UTC timestamp already in `year + 1`).
  Future<List<ReadingEvent>> fetchForYear(int year) async {
    final offline = this.offline;
    if (offline != null && offline.isActive) {
      final pending = await offline.drainBeforeRead();
      if (pending || offline.shouldQueue) {
        final cached = await offline.readEvents(year);
        if (cached != null) return _parseEvents(cached);
      }
    }

    try {
      final rows = await runSupabase(() {
        final start = DateTime(year).toUtc().toIso8601String();
        final end = DateTime(year + 1).toUtc().toIso8601String();
        return _client
            .from(_table)
            .select()
            .gte('occurred_at', start)
            .lt('occurred_at', end)
            .order('occurred_at');
      }, friendlyMessage: "We couldn't load your streak history.");
      await offline?.writeEvents(year, rows);
      return _parseEvents(rows);
    } on NetworkException {
      final cached = await offline?.readEvents(year);
      if (cached == null) rethrow;
      return _parseEvents(cached);
    }
  }

  /// Oldest first, like the query — a cached year has locally appended
  /// rows at the end, which may be backdated.
  static List<ReadingEvent> _parseEvents(List<Map<String, dynamic>> rows) {
    final events = [for (final row in rows) ?ReadingEvent.fromRow(row)];
    events.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    return events;
  }

  /// Erases every row logged against [title] — what `delete <book>`
  /// does to its own journal history. `title` is the only link between
  /// a `reading_events` row and the book it was about (see [log]'s doc
  /// comment), so removing the book from the shelf removes its whole
  /// story here too, rather than leaving a trail of "started"/"read up
  /// to page..." lines for a book that no longer exists.
  Future<void> deleteForTitle(String title) async {
    final offline = this.offline;
    if (offline != null && await offline.mustQueueWrite()) {
      await _queueDeleteForTitle(offline, title);
      offline.syncSoon();
      return;
    }
    try {
      await runSupabase<void>(() async {
        await _client.from(_table).delete().eq('title', title);
      }, friendlyMessage: "We couldn't clear that book's history.");
      await offline?.removeEventsForTitle(title);
    } on NetworkException {
      if (offline == null || !offline.isActive) rethrow;
      await _queueDeleteForTitle(offline, title);
    }
  }

  Future<void> _queueDeleteForTitle(
    OfflineLibraryCache offline,
    String title,
  ) async {
    await offline.removeEventsForTitle(title);
    await offline.enqueue(
      PendingDelete(
        id: offline.newWriteId(),
        createdAt: DateTime.now().toUtc(),
        table: _table,
        column: 'title',
        value: title,
      ),
    );
  }
}
