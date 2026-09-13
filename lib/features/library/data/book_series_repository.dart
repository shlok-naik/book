import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/book.dart';
import '../domain/book_series.dart';
import '../domain/library_exception.dart';
import 'supabase_guard.dart';

/// Reads and writes series — the shared `book_series` table and the
/// `series_id`/`series_position` columns on `books`. Writes go only through
/// the `set_book_series` function (see its migration for the
/// first-writer-wins rule); reads are plain selects, since both tables are
/// readable by every signed-in reader.
class BookSeriesRepository {
  BookSeriesRepository({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  /// Files [bookId] under [seriesName], optionally at [position], and
  /// returns the book re-read with its series embedded.
  Future<Book> setSeries(
    String bookId,
    String seriesName, {
    double? position,
  }) async {
    final name = BookSeries.normalizeName(seriesName);
    if (name.isEmpty) {
      throw const InvalidInputException('Name the series first.');
    }
    if (name.length > BookSeries.maxNameLength) {
      throw const InvalidInputException(
        'Series names can be at most ${BookSeries.maxNameLength} characters.',
      );
    }
    if (position != null && (position <= 0 || position >= 10000)) {
      throw const InvalidInputException(
        'A series number has to be above zero.',
      );
    }

    try {
      return await runSupabase(() async {
        await _client.rpc<Map<String, dynamic>>(
          'set_book_series',
          params: {
            'p_book_id': bookId,
            'p_series_name': name,
            'p_position': position,
          },
        );
        final row = await _client
            .from('books')
            .select(Book.selectWithSeries)
            .eq('id', bookId)
            .single();
        return Book.fromRow(row);
      }, friendlyMessage: "We couldn't save that series.");
    } on RemoteDataException catch (error) {
      final cause = error.cause;
      if (cause is PostgrestException) {
        if (cause.hint == 'series_locked') {
          throw const InvalidInputException(
            'That book is already filed in a series by another reader.',
          );
        }
        if (cause.code == 'P0002') {
          throw const InvalidInputException(
            "That book isn't on your shelf yet.",
          );
        }
      }
      rethrow;
    }
  }

  /// The series called [name] (ignoring case and spacing), or null.
  Future<BookSeries?> findByName(String name) {
    final clean = BookSeries.normalizeName(name);
    if (clean.isEmpty) return Future.value(null);
    return runSupabase(() async {
      final rows = await _client
          .from('book_series')
          .select()
          .ilike('name', escapeLikePattern(clean))
          .limit(5);
      for (final row in rows) {
        final series = BookSeries.fromRow(row);
        if (series != null && series.matches(clean)) return series;
      }
      return null;
    }, friendlyMessage: "We couldn't look up that series.");
  }

  /// Every cached book filed under [seriesId], in series order: numbered
  /// books by number, then unnumbered ones by title.
  Future<List<Book>> booksInSeries(String seriesId) {
    return runSupabase(() async {
      final rows = await _client
          .from('books')
          .select(Book.selectWithSeries)
          .eq('series_id', seriesId)
          .limit(200);
      return BookSeries.sortBooks([for (final row in rows) Book.fromRow(row)]);
    }, friendlyMessage: "We couldn't load that series.");
  }
}
