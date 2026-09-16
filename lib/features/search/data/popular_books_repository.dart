import 'package:supabase_flutter/supabase_flutter.dart';

import '../../library/data/supabase_guard.dart';
import '../../library/domain/book.dart';

/// The books most cactus readers have on their shelves — the search tab's
/// "our readers read" row. Backed by the `popular_books` security-definer
/// function, which only ever returns shared catalogue rows, and only for a
/// book at least two readers have.
class PopularBooksRepository {
  PopularBooksRepository({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  Future<List<Book>> fetch({int limit = 20}) {
    return runSupabase(() async {
      final rows = await _client.rpc<List<dynamic>>(
        'popular_books',
        params: {'p_limit': limit},
      );
      return [
        for (final row in rows)
          if (row is Map<String, dynamic>) Book.fromRow(row),
      ];
    }, friendlyMessage: "Couldn't load popular books.");
  }
}
