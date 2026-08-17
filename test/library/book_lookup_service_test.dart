import 'dart:convert';

import 'package:book/features/library/data/book_cache_repository.dart';
import 'package:book/features/library/data/google_book.dart';
import 'package:book/features/library/data/google_books_api_client.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/book_lookup_service.dart';
import 'package:book/features/library/domain/library_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// In-memory stand-in for the Supabase cache. Counts calls so the tests
/// can assert that a cache hit really does skip the network.
class FakeBookCacheRepository extends BookCacheRepository {
  FakeBookCacheRepository({this.readFailure});

  /// When set, every read throws it — used to prove a broken cache
  /// degrades to a miss instead of failing the lookup.
  final LibraryException? readFailure;

  final List<Book> rows = [];
  int cacheWrites = 0;
  LibraryException? writeFailure;

  @override
  Future<Book?> findByTitle(String title, {String? author}) async {
    if (readFailure != null) throw readFailure!;
    final needle = title.trim().toLowerCase();
    for (final book in rows) {
      if (book.title.toLowerCase() == needle) return book;
    }
    return null;
  }

  @override
  Future<Book?> findByGoogleBooksId(String googleBooksId) async {
    if (readFailure != null) throw readFailure!;
    for (final book in rows) {
      if (book.googleBooksId == googleBooksId) return book;
    }
    return null;
  }

  @override
  Future<Book> cache(GoogleBook volume) async {
    cacheWrites++;
    if (writeFailure != null) throw writeFailure!;
    final stored = Book(
      id: 'row-${rows.length + 1}',
      googleBooksId: volume.id,
      title: volume.title,
      author: volume.authorLine,
      coverUrl: volume.thumbnailUrl,
      pageCount: volume.pageCount,
      description: volume.description,
    );
    rows.add(stored);
    return stored;
  }
}

/// Builds a Google Books "volumes" payload with a single volume.
String volumesJson({
  String id = 'gb-dune',
  String title = 'Dune',
  List<String> authors = const ['Frank Herbert'],
  int? pageCount = 412,
  String? thumbnail = 'http://books.google.com/dune.jpg',
}) {
  return jsonEncode({
    'totalItems': 1,
    'items': [
      {
        'id': id,
        'volumeInfo': {
          'title': title,
          'authors': authors,
          if (pageCount != null) 'pageCount': pageCount,
          if (thumbnail != null) 'imageLinks': {'thumbnail': thumbnail},
        },
      },
    ],
  });
}

void main() {
  late FakeBookCacheRepository cache;
  var googleCalls = 0;

  BookLookupService serviceWith(
    Future<http.Response> Function(http.Request) handler, {
    FakeBookCacheRepository? withCache,
  }) {
    cache = withCache ?? FakeBookCacheRepository();
    return BookLookupService(
      cache: cache,
      googleBooks: GoogleBooksApiClient(
        client: MockClient((request) {
          googleCalls++;
          return handler(request);
        }),
      ),
    );
  }

  setUp(() => googleCalls = 0);

  group('BookLookupService.findOrFetch', () {
    test('rejects an empty query before any I/O', () async {
      final service = serviceWith((_) async => http.Response('{}', 200));

      await expectLater(
        service.findOrFetch('   '),
        throwsA(isA<InvalidInputException>()),
      );
      expect(googleCalls, 0);
    });

    test('rejects an absurdly long query', () async {
      final service = serviceWith((_) async => http.Response('{}', 200));

      await expectLater(
        service.findOrFetch('x' * (BookLookupService.maxQueryLength + 1)),
        throwsA(isA<InvalidInputException>()),
      );
      expect(googleCalls, 0);
    });

    test('a cache hit never touches Google Books', () async {
      final seeded = FakeBookCacheRepository()
        ..rows.add(
          const Book(
            id: 'row-1',
            googleBooksId: 'gb-dune',
            title: 'Dune',
            author: 'Frank Herbert',
            pageCount: 412,
          ),
        );
      final service = serviceWith(
        (_) async => http.Response(volumesJson(), 200),
        withCache: seeded,
      );

      final book = await service.findOrFetch('dune');

      expect(book.id, 'row-1');
      expect(googleCalls, 0);
      expect(seeded.cacheWrites, 0);
    });

    test('a cache miss fetches, writes back, and the next lookup hits '
        'the cache', () async {
      final service = serviceWith(
        (_) async => http.Response(volumesJson(), 200),
      );

      final first = await service.findOrFetch('Dune');
      expect(first.googleBooksId, 'gb-dune');
      expect(first.pageCount, 412);
      // http:// thumbnails are upgraded on the way in.
      expect(first.coverUrl, startsWith('https://'));
      expect(googleCalls, 1);
      expect(cache.cacheWrites, 1);

      final second = await service.findOrFetch('Dune');
      expect(second.id, first.id);
      expect(googleCalls, 1, reason: 'second lookup must be served by cache');
      expect(cache.cacheWrites, 1);
    });

    test('does not write a duplicate when the volume is already cached '
        'under a different title spelling', () async {
      final seeded = FakeBookCacheRepository()
        ..rows.add(
          const Book(
            id: 'row-1',
            googleBooksId: 'gb-dune',
            title: 'Dune: Deluxe Edition',
            author: 'Frank Herbert',
          ),
        );
      final service = serviceWith(
        (_) async => http.Response(volumesJson(), 200),
        withCache: seeded,
      );

      final book = await service.findOrFetch('dune');

      expect(book.id, 'row-1');
      expect(googleCalls, 1, reason: 'title lookup misses, so Google is asked');
      expect(seeded.cacheWrites, 0, reason: 'google id already cached');
    });

    test('picks the exact title match over the API ordering', () async {
      final payload = jsonEncode({
        'items': [
          {
            'id': 'gb-guide',
            'volumeInfo': {'title': 'A Study Guide for Dune'},
          },
          {
            'id': 'gb-dune',
            'volumeInfo': {
              'title': 'Dune',
              'authors': ['Frank Herbert'],
            },
          },
        ],
      });
      final service = serviceWith((_) async => http.Response(payload, 200));

      final book = await service.findOrFetch('dune');
      expect(book.googleBooksId, 'gb-dune');
    });

    test('reports no results as BookNotFoundException', () async {
      final service = serviceWith(
        (_) async => http.Response(jsonEncode({'totalItems': 0}), 200),
      );

      await expectLater(
        service.findOrFetch('asdkjhasd'),
        throwsA(
          isA<BookNotFoundException>().having(
            (e) => e.message,
            'message',
            contains('No books found'),
          ),
        ),
      );
    });

    test('maps a Google Books 5xx to a retryable NetworkException', () async {
      final service = serviceWith((_) async => http.Response('boom', 503));

      await expectLater(
        service.findOrFetch('Dune'),
        throwsA(isA<NetworkException>()),
      );
    });

    test('maps a Google Books 4xx to RemoteDataException', () async {
      final service = serviceWith((_) async => http.Response('bad key', 403));

      await expectLater(
        service.findOrFetch('Dune'),
        throwsA(isA<RemoteDataException>()),
      );
    });

    test('maps a malformed body to RemoteDataException', () async {
      final service = serviceWith(
        (_) async => http.Response('<html>not json</html>', 200),
      );

      await expectLater(
        service.findOrFetch('Dune'),
        throwsA(isA<RemoteDataException>()),
      );
    });

    test('survives a missing cover and page count', () async {
      final service = serviceWith(
        (_) async => http.Response(
          volumesJson(pageCount: null, thumbnail: null, authors: const []),
          200,
        ),
      );

      final book = await service.findOrFetch('Dune');
      expect(book.coverUrl, isNull);
      expect(book.pageCount, isNull);
      expect(book.author, Book.unknownAuthor);
    });

    test('a failing cache read degrades to a Google Books lookup', () async {
      final broken = FakeBookCacheRepository(
        readFailure: const NetworkException('cache down'),
      );
      final service = serviceWith(
        (_) async => http.Response(volumesJson(), 200),
        withCache: broken,
      );

      final book = await service.findOrFetch('Dune');
      expect(book.title, 'Dune');
      expect(googleCalls, 1);
    });

    test('a failing cache write is surfaced, not swallowed', () async {
      final broken = FakeBookCacheRepository()
        ..writeFailure = const RemoteDataException('write rejected');
      final service = serviceWith(
        (_) async => http.Response(volumesJson(), 200),
        withCache: broken,
      );

      await expectLater(
        service.findOrFetch('Dune'),
        throwsA(isA<RemoteDataException>()),
      );
    });
  });
}
