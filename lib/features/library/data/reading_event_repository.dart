import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/reading_event.dart';
import 'supabase_guard.dart';

/// Reads and writes the Supabase `reading_events` table — one row per
/// shelf command that actually took effect (see `supabase/schema.sql`),
/// which the streaks page groups by day to decide what to draw.
///
/// Like `UserBookRepository`, every row belongs to the one signed-in
/// reader; `user_id` is never set by the app itself, RLS and the column
/// default handle it.
class ReadingEventRepository {
  ReadingEventRepository({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  static const _table = 'reading_events';

  /// Records that [type] happened just now, against [title] — carried
  /// along purely so the day-detail sheet can list "started Dune" rather
  /// than just "started". Fire-and-forget from the caller's side — a
  /// failed log must never surface as a failed shelf command, so callers
  /// wrap this in `unawaited(...catchError(...))` rather than awaiting it
  /// inline.
  Future<void> log(ReadingEventType type, {required String title}) {
    return runSupabase<void>(() async {
      await _client.from(_table).insert({
        'action': type.wireValue,
        'title': title,
      });
    }, friendlyMessage: "We couldn't record that.");
  }

  /// Every event in [year], oldest first — enough for the streaks page
  /// to group into days and pick a symbol for each.
  ///
  /// The query window is [year]'s boundaries in *local* time, converted
  /// to UTC — matching how the streaks page groups rows back by local
  /// day. Querying a plain UTC year here would clip or leak boundary
  /// events for any reader not on UTC (e.g. a late Dec 31 local event
  /// with a UTC timestamp already in `year + 1`).
  Future<List<ReadingEvent>> fetchForYear(int year) {
    return runSupabase(() async {
      final start = DateTime(year).toUtc().toIso8601String();
      final end = DateTime(year + 1).toUtc().toIso8601String();
      final rows = await _client
          .from(_table)
          .select()
          .gte('occurred_at', start)
          .lt('occurred_at', end)
          .order('occurred_at');

      return [for (final row in rows) ?ReadingEvent.fromRow(row)];
    }, friendlyMessage: "We couldn't load your streak history.");
  }
}
