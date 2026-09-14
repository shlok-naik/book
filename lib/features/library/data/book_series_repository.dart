import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/book_series.dart';
import '../domain/collections.dart';
import '../domain/library_exception.dart';
import 'supabase_guard.dart';

/// Reads and writes the reader's own series — the private `series` table,
/// and the `series_id`/`series_position` columns on `user_books`.
///
/// Series follow the make-first design (see `collections.dart`): a series is
/// made with [makeSeries] (`make series`, or the "+" panel's series tab) and
/// only then applied to a book with [setSeries] (`add series`). Private to
/// the reader who made it, like `shelves` and `tags` — never shared with
/// anyone else, and never joined to a name another reader already picked.
class BookSeriesRepository {
  BookSeriesRepository({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  /// Postgres' unique_violation — a name the reader already has.
  static const _uniqueViolation = '23505';

  /// Makes a series called [name]. Throws [InvalidInputException] for an
  /// invalid name or one the reader already has.
  Future<BookSeries> makeSeries(String name) async {
    final clean = CollectionNames.validateSeries(name);
    try {
      return await runSupabase(() async {
        final row = await _client
            .from('series')
            .insert({'name': clean})
            .select()
            .single();
        final series = BookSeries.fromRow(row);
        if (series == null) {
          throw RemoteDataException(
            "We couldn't make that series.",
            cause: 'unparseable series row: $row',
          );
        }
        return series;
      }, friendlyMessage: "We couldn't make that series.");
    } on RemoteDataException catch (error) {
      final cause = error.cause;
      if (cause is PostgrestException && cause.code == _uniqueViolation) {
        throw InvalidInputException('You already have a series "$clean".');
      }
      rethrow;
    }
  }

  /// Every series on the reader's own list, alphabetically — what
  /// `add series` accepts and the "+" panel lists.
  Future<List<BookSeries>> fetchMySeries() {
    return runSupabase(() async {
      final rows = await _client.from('series').select().order('name');
      return [for (final row in rows) ?BookSeries.fromRow(row)];
    }, friendlyMessage: "We couldn't load your series.");
  }

  /// Files [userBookId] under [seriesId] at [position] — the shelf row's
  /// own `series_id`/`series_position`. The composite foreign key on
  /// `user_books` guarantees [seriesId] is one of the caller's own series,
  /// so there is nothing else to validate server-side.
  Future<void> setSeries(
    String userBookId,
    String seriesId, {
    double? position,
  }) {
    if (position != null && (position <= 0 || position >= 10000)) {
      throw const InvalidInputException(
        'A series number has to be above zero.',
      );
    }
    return runSupabase<void>(() async {
      await _client
          .from('user_books')
          .update({'series_id': seriesId, 'series_position': position})
          .eq('id', userBookId);
    }, friendlyMessage: "We couldn't save that series.");
  }

  /// Clears [userBookId]'s `series_id`/`series_position` — taking a book
  /// out of a series without moving it anywhere else.
  Future<void> clearSeries(String userBookId) {
    return runSupabase<void>(() async {
      await _client
          .from('user_books')
          .update({'series_id': null, 'series_position': null})
          .eq('id', userBookId);
    }, friendlyMessage: "We couldn't remove that series.");
  }

  /// Unmakes a series the reader made — every book filed under it loses
  /// that filing too (the composite FK's `on delete set null`).
  Future<void> deleteSeries(String id) {
    return runSupabase<void>(() async {
      await _client.from('series').delete().eq('id', id);
    }, friendlyMessage: "We couldn't remove that series.");
  }
}
