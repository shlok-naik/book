import 'package:flutter/foundation.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../library/data/google_book.dart';
import '../../../library/domain/book_lookup_service.dart';
import '../../../library/domain/library_book.dart';
import '../../../library/domain/library_exception.dart';
import '../../domain/reading_taste.dart';
import '../../domain/recommendation_seeds.dart';

/// One recommendation row's state.
class RecommendationRow {
  const RecommendationRow({
    required this.seed,
    this.books = const [],
    this.loading = false,
    this.error,
  });

  final RecommendationSeed seed;
  final List<GoogleBook> books;
  final bool loading;
  final String? error;
}

/// The search tab's Google Books half: the results for what's typed, and
/// the recommendation rows under an empty search bar. The reader's own
/// shelf matches are filtered on the page itself, straight from
/// `LibraryController` — they need no fetch.
///
/// Per-page state, like `BookDetailController`: built by the page from the
/// `LibraryController.lookup` it already has, so no HTTP client is made in
/// a widget.
class BookSearchController extends ChangeNotifier {
  BookSearchController({required this.lookup});

  final BookLookupService lookup;

  String _query = '';
  List<GoogleBook> _results = const [];
  bool _searching = false;
  String? _error;

  /// Bumped per search, so a slow answer to an old query never replaces the
  /// results of a newer one.
  int _generation = 0;

  List<RecommendationSeed> _seeds = const [];
  List<RecommendationRow> _rows = const [];

  bool _disposed = false;

  String get query => _query;
  List<GoogleBook> get results => _results;
  bool get isSearching => _searching;
  String? get errorMessage => _error;
  List<RecommendationRow> get recommendations => _rows;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Searches Google Books for [query]. An empty query clears the results.
  /// Never throws — a failure is [errorMessage].
  Future<void> search(String query) async {
    final trimmed = query.trim();
    final generation = ++_generation;
    _query = trimmed;
    if (trimmed.isEmpty) {
      _results = const [];
      _searching = false;
      _error = null;
      _notify();
      return;
    }
    _searching = true;
    _error = null;
    _notify();
    try {
      final found = await lookup.searchCatalogue(trimmed);
      if (generation != _generation) return;
      _results = found;
    } on LibraryException catch (error) {
      if (generation != _generation) return;
      _results = const [];
      _error = error.message;
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'BookSearchController',
        'Searching Google Books failed unexpectedly.',
        error: error,
        stackTrace: stackTrace,
      );
      if (generation != _generation) return;
      _results = const [];
      _error = 'Search failed. Try again.';
    }
    _searching = false;
    _notify();
  }

  /// Fills the recommendation rows for [books] — the reader's shelf. Only
  /// refetches when the rows it would show changed ([RecommendationSeeds]),
  /// so opening the tab again, or a progress update, costs nothing.
  Future<void> loadRecommendations(
    List<LibraryBook> books, {
    List<ReadingTaste> tastes = const [],
  }) async {
    final seeds = RecommendationSeeds.from(books, tastes: tastes);
    if (listEquals(seeds, _seeds)) return;
    _seeds = seeds;
    _rows = [
      for (final seed in seeds) RecommendationRow(seed: seed, loading: true),
    ];
    _notify();

    final onShelf = {for (final entry in books) entry.book.googleBooksId};
    await Future.wait([
      for (final (i, seed) in seeds.indexed) _loadRow(i, seed, onShelf),
    ]);
  }

  Future<void> _loadRow(
    int index,
    RecommendationSeed seed,
    Set<String?> onShelf,
  ) async {
    RecommendationRow row;
    try {
      final found = await lookup.searchCatalogue(seed.query);
      final seen = <String>{};
      row = RecommendationRow(
        seed: seed,
        books: [
          for (final book in found)
            if (!onShelf.contains(book.id) &&
                seen.add(book.title.toLowerCase()))
              book,
        ],
      );
    } on LibraryException catch (error) {
      row = RecommendationRow(seed: seed, error: error.message);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'BookSearchController',
        'Loading recommendations failed unexpectedly.',
        error: error,
        stackTrace: stackTrace,
      );
      row = RecommendationRow(seed: seed, error: "Couldn't load these.");
    }
    // The seeds may have moved on while this row loaded.
    if (index >= _rows.length || _rows[index].seed != seed) return;
    _rows = [..._rows]..[index] = row;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
