import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/memory.dart';
import '../domain/memory_exception.dart';

/// Reads and writes the Supabase `memories` table — one row per
/// `remember <book> :: <note>` command that actually took effect. Every
/// row belongs to the one signed-in reader; `user_id` is never set by
/// the app itself, RLS and the column default handle it (see
/// `supabase/migrations/20260901000000_memories.sql`).
class MemoryRepository {
  MemoryRepository({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  static const _table = 'memories';
  static const _timeout = Duration(seconds: 10);

  /// Every memory the reader has saved, most recent first.
  Future<List<Memory>> fetchAll() {
    return _run(() async {
      final rows = await _client
          .from(_table)
          .select()
          .order('created_at', ascending: false);
      return [for (final row in rows) ?Memory.fromRow(row)];
    }, friendlyMessage: "We couldn't load your memories.");
  }

  /// Saves a new memory and returns the row Supabase actually wrote —
  /// its `created_at`/`id` come from the database rather than being
  /// guessed client-side, so the caller's optimistic entry can be
  /// swapped for the real one once this resolves.
  Future<Memory> add({String? bookTitle, required String note}) {
    return _run(() async {
      final row = await _client
          .from(_table)
          .insert({'book_title': bookTitle, 'note': note})
          .select()
          .single();
      final memory = Memory.fromRow(row);
      if (memory == null) {
        throw const MemoryException("That memory couldn't be saved.");
      }
      return memory;
    }, friendlyMessage: "That memory couldn't be saved.");
  }

  Future<void> delete(String id) {
    return _run(() async {
      await _client.from(_table).delete().eq('id', id);
    }, friendlyMessage: "That memory couldn't be removed.");
  }

  /// Translates driver failures into a [MemoryException] carrying
  /// [friendlyMessage] — mirrors `runSupabase` in the library feature's
  /// own data layer; kept local to this feature rather than shared
  /// (see `MemoryException`'s own doc comment) since this is the one
  /// other place in the app with the same three failure shapes to
  /// translate.
  Future<T> _run<T>(
    Future<T> Function() action, {
    required String friendlyMessage,
  }) async {
    try {
      return await action().timeout(_timeout);
    } on MemoryException {
      rethrow;
    } on TimeoutException catch (error) {
      throw MemoryException(
        'That took too long — try again in a moment.',
        cause: error,
      );
    } on SocketException catch (error) {
      throw MemoryException(
        "You're offline — connect to the internet and try again.",
        cause: error,
      );
    } on http.ClientException catch (error) {
      throw MemoryException(friendlyMessage, cause: error);
    } on PostgrestException catch (error) {
      throw MemoryException(friendlyMessage, cause: error);
    } on Object catch (error) {
      throw MemoryException(friendlyMessage, cause: error);
    }
  }
}
