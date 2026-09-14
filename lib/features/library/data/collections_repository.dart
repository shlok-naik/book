import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/collections.dart';
import '../domain/library_exception.dart';
import 'supabase_guard.dart';

/// Reads and creates the reader's own standalone collections — the private
/// `shelves` and `tags` tables. (Series are private too, but live in their
/// own `BookSeriesRepository` since they also carry a shelf row's own
/// `series_id`/`series_position`.)
///
/// These are the *creation* half of the make-first design: every path that
/// makes a shelf or a tag — `make shelf`/`make tag`, the library page's "+"
/// panel, a Goodreads import making the file's tags — ends in [createShelf]
/// or [createTag]. Applying one to a book is a different write, elsewhere
/// (`UserBookRepository.changeShelf`, `BookNotesRepository.addTag`).
///
/// Like every per-reader table, `user_id` is never sent from here: the column
/// default and RLS own it.
class CollectionsRepository {
  CollectionsRepository({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  /// Postgres' unique_violation — a name the reader already has.
  static const _uniqueViolation = '23505';

  /// Postgres' check_violation — for `shelves`, a reserved built-in name
  /// that got past [CollectionNames.validateShelf] (an older client).
  static const _checkViolation = '23514';

  /// Every shelf the reader made, oldest first — the order they appear on
  /// the library page, after the four built-in shelves.
  Future<List<Shelf>> fetchShelves() {
    return runSupabase(() async {
      final rows = await _client.from('shelves').select().order('created_at');
      return [for (final row in rows) ?Shelf.fromRow(row)];
    }, friendlyMessage: "We couldn't load your shelves.");
  }

  /// Every tag the reader made, alphabetically.
  Future<List<ReaderTag>> fetchTags() {
    return runSupabase(() async {
      final rows = await _client.from('tags').select().order('name');
      return [for (final row in rows) ?ReaderTag.fromRow(row)];
    }, friendlyMessage: "We couldn't load your tags.");
  }

  /// Makes a shelf called [name]. Throws [InvalidInputException] for an
  /// invalid name or one the reader already has.
  Future<Shelf> createShelf(String name) async {
    final clean = CollectionNames.validateShelf(name);
    try {
      return await runSupabase(() async {
        final row = await _client
            .from('shelves')
            .insert({'name': clean})
            .select()
            .single();
        return _parsed(Shelf.fromRow(row), row, "We couldn't make that shelf.");
      }, friendlyMessage: "We couldn't make that shelf.");
    } on RemoteDataException catch (error) {
      final cause = error.cause;
      if (cause is PostgrestException) {
        if (cause.code == _uniqueViolation) {
          throw InvalidInputException('You already have a shelf "$clean".');
        }
        if (cause.code == _checkViolation) {
          throw InvalidInputException(
            '"$clean" is already one of your built-in shelves.',
          );
        }
      }
      rethrow;
    }
  }

  /// Makes a tag called [name]. Throws [InvalidInputException] for an
  /// invalid name or one the reader already has.
  Future<ReaderTag> createTag(String name) async {
    final clean = CollectionNames.validateTag(name);
    try {
      return await runSupabase(() async {
        final row = await _client
            .from('tags')
            .insert({'name': clean})
            .select()
            .single();
        return _parsed(
          ReaderTag.fromRow(row),
          row,
          "We couldn't make that tag.",
        );
      }, friendlyMessage: "We couldn't make that tag.");
    } on RemoteDataException catch (error) {
      final cause = error.cause;
      if (cause is PostgrestException && cause.code == _uniqueViolation) {
        throw InvalidInputException('You already have a tag "$clean".');
      }
      rethrow;
    }
  }

  static T _parsed<T>(T? value, Map<String, dynamic> row, String message) {
    if (value == null) {
      throw RemoteDataException(message, cause: 'unparseable row: $row');
    }
    return value;
  }
}
