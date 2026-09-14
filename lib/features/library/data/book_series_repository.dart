import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/book.dart';
import '../domain/book_series.dart';
import '../domain/collections.dart';
import '../domain/library_exception.dart';
import 'supabase_guard.dart';

/// Outcome of [BookSeriesRepository.makeSeries].
class MadeSeries {
  const MadeSeries(
    this.series, {
    required this.createdNew,
    required this.alreadyYours,
  });

  final BookSeries series;

  /// Nobody had a series by this name before — it is brand new.
  final bool createdNew;

  /// The reader had already made this series; nothing changed.
  final bool alreadyYours;
}

/// Reads and writes series — the shared `book_series` table, the reader's
/// own `reader_series` list, and the `series_id`/`series_position` columns
/// on `books`.
///
/// Series follow the make-first design (see `collections.dart`): a series is
/// made with [makeSeries] (`make series`, or the "+" panel's series tab) and
/// only then applied to a book with [setSeries] (`add series`). Both writes
/// go through security-definer functions — `make_book_series` and
/// `set_book_series`, see `20260916000000_standalone_collections.sql` for the
/// rules; reads are plain selects.
class BookSeriesRepository {
  BookSeriesRepository({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  /// Makes a series called [name] and puts it on the reader's own list —
  /// the one creation path for series. Series are shared, so a name another
  /// reader already made is *joined* rather than refused
  /// ([MadeSeries.createdNew] false); only the reader's own duplicate
  /// reports [MadeSeries.alreadyYours]. Deciding whether that is a failure
  /// is the caller's call — a Goodreads import is happy either way.
  Future<MadeSeries> makeSeries(String name) async {
    final clean = CollectionNames.validateSeries(name);
    return runSupabase(() async {
      final result = await _client.rpc<Map<String, dynamic>>(
        'make_book_series',
        params: {'p_name': clean},
      );
      final series = BookSeries.fromRow(result);
      if (series == null) {
        throw RemoteDataException(
          "We couldn't make that series.",
          cause: 'unparseable make_book_series result: $result',
        );
      }
      return MadeSeries(
        series,
        createdNew: result['created'] == true,
        alreadyYours: result['already_yours'] == true,
      );
    }, friendlyMessage: "We couldn't make that series.");
  }

  /// Every series on the reader's own list, alphabetically — what
  /// `add series` accepts and the "+" panel lists.
  Future<List<BookSeries>> fetchMySeries() {
    return runSupabase(() async {
      final rows = await _client
          .from('reader_series')
          .select('series:book_series(id, name)');
      final series = [
        for (final row in rows)
          if (row['series'] case final Map<String, dynamic> embedded)
            ?BookSeries.fromRow(embedded),
      ];
      series.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return series;
    }, friendlyMessage: "We couldn't load your series.");
  }

  /// Files [bookId] under [seriesName], optionally at [position], and
  /// returns the book re-read with its series embedded. The series must
  /// already be on the reader's list ([makeSeries]); this never creates one.
  Future<Book> setSeries(
    String bookId,
    String seriesName, {
    double? position,
  }) async {
    final name = CollectionNames.validateSeries(seriesName);
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
        if (cause.hint == 'series_missing') {
          throw InvalidInputException(
            'No series called "$name" yet — make it first with '
            'make series $name.',
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
