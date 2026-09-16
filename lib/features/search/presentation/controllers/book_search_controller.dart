import 'package:flutter/foundation.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../library/data/google_book.dart';
import '../../../library/domain/book_lookup_service.dart';
import '../../../library/domain/library_book.dart';
import '../../../library/domain/library_exception.dart';
import '../../data/popular_books_repository.dart';
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
  BookSearchController({required this.lookup, this.popularBooks});

  final BookLookupService lookup;

  /// The "our readers read" row's source. Null skips that row.
  final PopularBooksRepository? popularBooks;

  /// How many rows fetch at once. Google Books answers a burst of parallel
  /// searches with 503s, so the rows fill in a couple at a time.
  static const rowConcurrency = 2;

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

  /// Rows still loading or with books — a row that came back empty (or,
  /// for "our readers read", failed) is left out rather than shown blank.
  List<RecommendationRow> get recommendations => [
    for (final row in _rows)
      if (row.loading ||
          row.books.isNotEmpty ||
          (row.error != null && row.seed.source == SeedSource.catalogue))
        row,
  ];

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Most ratings on Google Books first — the nearest thing it has to
  /// "most popular". Stable, so Google's own relevance order breaks ties
  /// (and keeps volumes with no ratings in their original order).
  static List<GoogleBook> byPopularity(List<GoogleBook> books) {
    final indexed = books.indexed.toList()
      ..sort((a, b) {
        final byCount = (b.$2.ratingsCount ?? 0).compareTo(
          a.$2.ratingsCount ?? 0,
        );
        return byCount != 0 ? byCount : a.$1.compareTo(b.$1);
      });
    return [for (final (_, book) in indexed) book];
  }

  /// Searches Google Books for [query], most popular first. An empty query
  /// clears the results. Never throws — a failure is [errorMessage].
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
      _results = byPopularity(found);
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
    final seeds = [
      for (final seed in RecommendationSeeds.from(books, tastes: tastes))
        if (seed.source != SeedSource.readers || popularBooks != null) seed,
    ];
    if (listEquals(seeds, _seeds)) return;
    _seeds = seeds;
    _rows = [
      for (final seed in seeds) RecommendationRow(seed: seed, loading: true),
    ];
    _notify();

    final onShelf = {for (final entry in books) entry.book.googleBooksId};
    for (var start = 0; start < seeds.length; start += rowConcurrency) {
      if (_disposed || !identical(_seeds, seeds)) return;
      await Future.wait([
        for (var i = start; i < start + rowConcurrency && i < seeds.length; i++)
          _loadRow(i, seeds[i], onShelf),
      ]);
    }
  }

  Future<List<GoogleBook>> _fetch(RecommendationSeed seed) async {
    switch (seed.source) {
      case SeedSource.readers:
        final books = await popularBooks!.fetch();
        return [for (final book in books) GoogleBook.fromBook(book)];
      case SeedSource.catalogue:
        var found = await lookup.searchCatalogue(
          seed.query,
          maxResults: 40,
          orderBy: seed.orderBy,
        );
        if (seed.maxPages case final max?) {
          found = [
            for (final book in found)
              if ((book.pageCount ?? 0) > 0 && book.pageCount! <= max) book,
          ];
        }
        return seed.byPopularity ? byPopularity(found) : found;
    }
  }

  Future<void> _loadRow(
    int index,
    RecommendationSeed seed,
    Set<String?> onShelf,
  ) async {
    RecommendationRow row;
    try {
      final found = await _fetch(seed);
      final seen = <String>{};
      row = RecommendationRow(
        seed: seed,
        books: [
          for (final book in found)
            if (!onShelf.contains(book.id) &&
                seen.add(book.title.toLowerCase()))
              book,
        ].take(20).toList(),
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
