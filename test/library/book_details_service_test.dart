import 'dart:convert';

import 'package:book/features/library/data/book_details_repository.dart';
import 'package:book/features/library/data/google_book.dart';
import 'package:book/features/library/data/google_books_api_client.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/book_details_service.dart';
import 'package:book/features/library/domain/book_edition.dart';
import 'package:book/features/library/domain/library_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The detail page's caching policy — the same cache-first shape as
/// `BookLookupService`: Supabase first, Google Books only on a miss, write
/// back. What these pin down is when Google Books is (and is not) called.

const _dune = Book(
  id: 'book-1',
  googleBooksId: 'gb-dune',
  title: 'Dune',
  author: 'Frank Herbert',
  description: 'Short blurb.',
  pageCount: 400,
);

Book _withDetails(Book book) => Book(
  id: book.id,
  googleBooksId: book.googleBooksId,
  title: book.title,
  author: book.author,
  description: 'Full blurb.',
  publisher: 'Ace',
  detailsFetchedAt: DateTime.utc(2026),
);

Book _withEditionsFetched(Book book) => Book(
  id: book.id,
  googleBooksId: book.googleBooksId,
  title: book.title,
  author: book.author,
  editionsFetchedAt: DateTime.utc(2026),
);

/// In-memory stand-in for the `books` detail columns and `book_editions`.
class FakeDetailsCache extends BookDetailsRepository {
  Book? stored;
  List<BookEdition> editions = [];
  LibraryException? readFailure;
  LibraryException? writeFailure;
  int detailWrites = 0;
  List<BookEdition>? lastCachedEditions;

  @override
  Future<Book?> fetchBook(String bookId) async {
    if (readFailure != null) throw readFailure!;
    return stored;
  }

  @override
  Future<Book> cacheDetails(GoogleBook volume, {String? description}) async {
    if (writeFailure != null) throw writeFailure!;
    detailWrites++;
    stored = Book(
      id: 'book-1',
      googleBooksId: volume.id,
      title: volume.title,
      author: volume.authorLine,
      description: description,
      publisher: volume.publisher,
      detailsFetchedAt: DateTime.utc(2026),
    );
    return stored!;
  }

  @override
  Future<List<BookEdition>> fetchEditions(String bookId) async {
    if (readFailure != null) throw readFailure!;
    return editions;
  }

  @override
  Future<List<BookEdition>> cacheEditions(
    String bookId,
    List<BookEdition> fresh,
  ) async {
    if (writeFailure != null) throw writeFailure!;
    lastCachedEditions = fresh;
    editions = [
      for (var i = 0; i < fresh.length; i++)
        BookEdition(
          id: 'edition-$i',
          googleBooksId: fresh[i].googleBooksId,
          title: fresh[i].title,
          author: fresh[i].author,
          format: fresh[i].format,
          publishedDate: fresh[i].publishedDate,
        ),
    ];
    return editions;
  }
}

/// Google Books that counts its calls and serves a volume and a search.
class GoogleStub {
  int volumeCalls = 0;
  int searchCalls = 0;
  int status = 200;
  String? lastQuery;

  GoogleBooksApiClient client() => GoogleBooksApiClient(
    client: MockClient((request) async {
      if (status != 200) return http.Response('nope', status);
      if (request.url.path.endsWith('/volumes')) {
        searchCalls++;
        lastQuery = request.url.queryParameters['q'];
        return http.Response(
          jsonEncode({
            'items': [
              _item('e1', ebook: true, date: '2010'),
              _item('p1', isbn: '9780441013593', date: '2005'),
              _item('other', title: 'Dune Messiah', isbn: '1'),
            ],
          }),
          200,
        );
      }
      volumeCalls++;
      return http.Response(
        jsonEncode({
          'id': 'gb-dune',
          'volumeInfo': {
            'title': 'Dune',
            'authors': ['Frank Herbert'],
            'publisher': 'Ace',
            'pageCount': 612,
            'description': '<p>Full <b>blurb</b>.</p>',
          },
        }),
        200,
      );
    }),
  );

  static Map<String, Object?> _item(
    String id, {
    String title = 'Dune',
    bool ebook = false,
    String? isbn,
    String? date,
  }) => {
    'id': id,
    'volumeInfo': {
      'title': title,
      'authors': ['Frank Herbert'],
      'printType': 'BOOK',
      'publishedDate': ?date,
      if (isbn != null)
        'industryIdentifiers': [
          {'type': 'ISBN_13', 'identifier': isbn},
        ],
    },
    'saleInfo': {'isEbook': ebook},
  };
}

void main() {
  late FakeDetailsCache cache;
  late GoogleStub google;
  late BookDetailsService service;

  setUp(() {
    cache = FakeDetailsCache();
    google = GoogleStub();
    service = BookDetailsService(cache: cache, googleBooks: google.client());
  });

  group('detailsFor', () {
    test('a book already carrying details never touches the network', () async {
      final book = _withDetails(_dune);
      expect(await service.detailsFor(book), same(book));
      expect(google.volumeCalls, 0);
    });

    test(
      'a stale shelf copy is refreshed from the cache, not Google',
      () async {
        cache.stored = _withDetails(_dune);

        final result = await service.detailsFor(_dune);

        expect(result.publisher, 'Ace');
        expect(google.volumeCalls, 0);
      },
    );

    test(
      'a miss fetches the volume, strips its HTML and writes it back',
      () async {
        final result = await service.detailsFor(_dune);

        expect(google.volumeCalls, 1);
        expect(cache.detailWrites, 1);
        expect(result.description, 'Full blurb.');
        expect(result.hasCachedDetails, isTrue);

        // The second visit is a cache hit.
        await service.detailsFor(_dune);
        expect(google.volumeCalls, 1);
      },
    );

    test('a failed cache read degrades to a miss', () async {
      cache.readFailure = const NetworkException('down');

      final result = await service.detailsFor(_dune);

      expect(result.publisher, 'Ace');
      expect(google.volumeCalls, 1);
    });

    test('a failed cache write still returns the fetched details', () async {
      cache.writeFailure = const RemoteDataException('rejected');

      final result = await service.detailsFor(_dune);

      expect(result.publisher, 'Ace');
      expect(result.description, 'Full blurb.');
      expect(result.hasCachedDetails, isFalse, reason: 'it was not cached');
      expect(
        result.pageCount,
        400,
        reason: "the shelf's page count is never replaced by the volume's",
      );
    });

    test('Google Books being unavailable is a friendly failure', () async {
      google.status = 503;
      await expectLater(
        service.detailsFor(_dune),
        throwsA(isA<NetworkException>()),
      );
    });

    test(
      'a rate-limited Google Books is retryable, not a data error',
      () async {
        google.status = 429;
        await expectLater(
          service.detailsFor(_dune),
          throwsA(isA<NetworkException>()),
        );
      },
    );

    test('a withdrawn volume is BookNotFound', () async {
      google.status = 404;
      await expectLater(
        service.detailsFor(_dune),
        throwsA(isA<BookNotFoundException>()),
      );
    });
  });

  group('editionsFor', () {
    test('a miss searches, filters to ebook/physical, and caches', () async {
      final editions = await service.editionsFor(_dune);

      expect(google.searchCalls, 1);
      expect(google.lastQuery, 'intitle:"Dune" inauthor:"Herbert"');
      expect(cache.lastCachedEditions!.map((e) => e.googleBooksId), [
        'e1',
        'p1',
      ]);
      expect(editions.every((e) => e.id != null), isTrue);
    });

    test('a book marked as fetched reads the cache only', () async {
      cache.editions = const [
        BookEdition(
          id: 'x',
          googleBooksId: 'x',
          title: 'Dune',
          author: 'Frank Herbert',
          format: EditionFormat.physical,
        ),
      ];

      final editions = await service.editionsFor(_withEditionsFetched(_dune));

      expect(editions.single.id, 'x');
      expect(google.searchCalls, 0);
    });

    test('"fetched, and there were none" is a hit, not a miss', () async {
      final editions = await service.editionsFor(_withEditionsFetched(_dune));
      expect(editions, isEmpty);
      expect(google.searchCalls, 0);
    });

    test('a stale shelf copy finds editions another reader cached', () async {
      cache.stored = _withEditionsFetched(_dune);
      cache.editions = const [
        BookEdition(
          id: 'x',
          googleBooksId: 'x',
          title: 'Dune',
          author: 'Frank Herbert',
          format: EditionFormat.ebook,
        ),
      ];

      await service.editionsFor(_dune);

      expect(google.searchCalls, 0);
    });

    test(
      'a failed write is an error — uncached editions cannot be owned',
      () async {
        cache.writeFailure = const RemoteDataException('rejected');
        await expectLater(
          service.editionsFor(_dune),
          throwsA(isA<RemoteDataException>()),
        );
      },
    );

    test(
      'a failed cache read on a fetched book falls back to Google',
      () async {
        cache.readFailure = const NetworkException('down');
        final editions = await service.editionsFor(_withEditionsFetched(_dune));
        expect(google.searchCalls, 1);
        expect(editions, hasLength(2));
      },
    );
  });
}
