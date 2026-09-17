import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/diagnostics/app_logger.dart';
import '../../library/data/google_book.dart';
import '../domain/recommendation_seeds.dart';

/// One discover row as it was last fetched.
class CachedRow {
  const CachedRow({required this.books, required this.fetchedAt});

  final List<GoogleBook> books;
  final DateTime fetchedAt;
}

/// The search tab's discover rows, kept on the device so the tab opens on
/// last time's books instantly and refreshes them underneath — rather than
/// on a blank page while Google Books (or its fallback) answers.
///
/// Only catalogue volumes are stored — the same public data every reader
/// sees, never anything from the reader's own shelf. Every read and write
/// degrades to "nothing cached": a broken cache costs a fetch, not a screen.
class RecommendationRowCache {
  RecommendationRowCache({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// The app's one cache, installed by `_bootstrap`. Null — as in widget
  /// tests, which never run `main` — means rows are always fetched.
  static RecommendationRowCache? installed;

  static const _key = 'search.discover_rows.v1';

  /// How many rows are kept — enough for every personal and browse row.
  static const maxRows = 16;

  final DateTime Function() _clock;
  Map<String, CachedRow>? _rows;

  /// A stable key for [seed]'s row.
  static String keyFor(RecommendationSeed seed) => [
    seed.source.name,
    seed.label,
    seed.query,
    seed.orderBy ?? '',
    seed.byPopularity,
    seed.maxPages ?? '',
  ].join('|');

  Future<Map<String, CachedRow>> readAll() async {
    if (_rows case final rows?) return rows;
    final rows = <String, CachedRow>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          for (final MapEntry(:key, :value) in decoded.entries) {
            if (value is! Map<String, dynamic>) continue;
            final at = DateTime.tryParse('${value['at']}');
            final books = value['books'];
            if (at == null || books is! List) continue;
            rows[key] = CachedRow(
              fetchedAt: at,
              books: [
                for (final book in books)
                  if (book is Map<String, dynamic>) GoogleBook.fromJson(book),
              ],
            );
          }
        }
      }
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'RecommendationRowCache',
        'Could not read the cached discover rows.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return _rows ??= rows;
  }

  Future<void> write(RecommendationSeed seed, List<GoogleBook> books) async {
    final rows = await readAll();
    rows[keyFor(seed)] = CachedRow(books: books, fetchedAt: _clock());
    if (rows.length > maxRows) {
      final oldest = rows.entries.toList()
        ..sort((a, b) => a.value.fetchedAt.compareTo(b.value.fetchedAt));
      for (final entry in oldest.take(rows.length - maxRows)) {
        rows.remove(entry.key);
      }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          for (final MapEntry(:key, :value) in rows.entries)
            key: {
              'at': value.fetchedAt.toIso8601String(),
              'books': [for (final book in value.books) book.toJson()],
            },
        }),
      );
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'RecommendationRowCache',
        'Could not save the discover rows.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
