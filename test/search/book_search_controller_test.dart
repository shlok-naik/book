import 'dart:convert';

import 'package:book/features/library/data/book_cache_repository.dart';
import 'package:book/features/library/data/google_book.dart';
import 'package:book/features/library/data/google_books_api_client.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/book_lookup_service.dart';
import 'package:book/features/search/data/recommendation_row_cache.dart';
import 'package:book/features/search/domain/recommendation_seeds.dart';
import 'package:book/features/search/presentation/controllers/book_search_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _NoCache extends BookCacheRepository {
  @override
  Future<Book?> findByGoogleBooksId(String googleBooksId) async => null;
}

/// A row cache held in memory instead of on the device.
class _MemoryRowCache extends RecommendationRowCache {
  _MemoryRowCache(this.rows);

  final Map<String, CachedRow> rows;
  final written = <String>[];

  @override
  Future<Map<String, CachedRow>> readAll() async => rows;

  @override
  Future<void> write(RecommendationSeed seed, List<GoogleBook> books) async {
    written.add(seed.label);
  }
}

void main() {
  late List<String> queries;

  BookSearchController controller(RecommendationRowCache cache) {
    queries = [];
    return BookSearchController(
      lookup: BookLookupService(
        cache: _NoCache(),
        googleBooks: GoogleBooksApiClient(
          client: MockClient((request) async {
            queries.add(request.url.queryParameters['q'] ?? '');
            return http.Response(
              jsonEncode({
                'items': [
                  {
                    'id': 'gb-${queries.length}',
                    'volumeInfo': {
                      'title': 'Fresh ${queries.length}',
                      'authors': ['Someone'],
                    },
                  },
                ],
              }),
              200,
            );
          }),
          authHeaders: () async => const {},
        ),
      ),
      rowCache: cache,
    );
  }

  const cachedBook = GoogleBook(
    id: 'gb-cached',
    title: 'Cached',
    authors: ['Someone'],
  );

  test('GoogleBook survives toJson and back', () {
    const book = GoogleBook(
      id: 'gb-1',
      title: 'Dune',
      authors: ['Frank Herbert'],
      thumbnailUrl: 'https://covers/x.jpg',
      pageCount: 412,
      categories: ['Fiction'],
      isbn13: '9780441013593',
      ratingsCount: 900,
      averageRating: 4.5,
      isEbook: true,
    );
    final back = GoogleBook.fromJson(book.toJson());
    expect(back.title, 'Dune');
    expect(back.thumbnailUrl, book.thumbnailUrl);
    expect(back.pageCount, 412);
    expect(back.isbn13, book.isbn13);
    expect(back.ratingsCount, 900);
    expect(back.isEbook, isTrue);
  });

  test('fresh cached rows show without fetching', () async {
    final seeds = [
      for (final seed in RecommendationSeeds.from(const []))
        if (seed.source == SeedSource.catalogue) seed,
    ];
    final cache = _MemoryRowCache({
      for (final seed in seeds)
        RecommendationRowCache.keyFor(seed): CachedRow(
          books: const [cachedBook],
          fetchedAt: DateTime.now(),
        ),
    });
    final search = controller(cache);
    addTearDown(search.dispose);

    await search.loadRecommendations(const []);

    expect(queries, isEmpty);
    expect(search.recommendations, hasLength(seeds.length));
    expect(search.recommendations.first.books.single.id, 'gb-cached');
  });

  test('stale cached rows show at once, then refresh', () async {
    final seeds = [
      for (final seed in RecommendationSeeds.from(const []))
        if (seed.source == SeedSource.catalogue) seed,
    ];
    final cache = _MemoryRowCache({
      RecommendationRowCache.keyFor(seeds.first): CachedRow(
        books: const [cachedBook],
        fetchedAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
    });
    final search = controller(cache);
    addTearDown(search.dispose);

    var sawCachedFirst = false;
    search.addListener(() {
      final first = search.recommendations.firstOrNull;
      if (queries.isEmpty && first?.books.firstOrNull?.id == 'gb-cached') {
        sawCachedFirst = true;
      }
    });
    await search.loadRecommendations(const []);

    expect(sawCachedFirst, isTrue);
    expect(queries, hasLength(seeds.length));
    expect(
      search.recommendations.first.books.single.title,
      startsWith('Fresh'),
    );
    expect(cache.written, contains(seeds.first.label));
  });
}
