import 'dart:convert';

import 'package:book/features/library/data/book_cache_repository.dart';
import 'package:book/features/library/data/google_book.dart';
import 'package:book/features/library/data/google_books_api_client.dart';
import 'package:book/features/library/data/open_library_client.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/book_lookup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _doc({
  String key = '/works/OL81634W',
  String title = 'Doctor Sleep',
  int? cover = 14652972,
  List<String> isbn = const ['9781451698848', '1451698844'],
  int? ratings = 120,
}) => {
  'key': key,
  'title': title,
  'author_name': ['Stephen King'],
  'cover_i': ?cover,
  'isbn': isbn,
  'number_of_pages_median': 531,
  'first_publish_year': 2013,
  'ratings_count': ?ratings,
};

/// Answers Open Library searches with [docs], recording each request.
OpenLibraryClient _openLibrary(
  List<Map<String, dynamic>> docs,
  List<Uri> requests,
) => OpenLibraryClient(
  client: MockClient((request) async {
    requests.add(request.url);
    return http.Response(jsonEncode({'docs': docs}), 200);
  }),
);

class _Cache extends BookCacheRepository {
  final cached = <GoogleBook>[];

  @override
  Future<Book?> findByTitle(String title, {String? author}) async => null;
  @override
  Future<Book?> findByGoogleBooksId(String id) async => null;
  @override
  Future<Book?> findByIsbn(String isbn) async => null;
  @override
  Future<Book> cache(GoogleBook volume) async {
    cached.add(volume);
    return Book(
      id: 'book-${volume.id}',
      googleBooksId: volume.id,
      title: volume.title,
      author: volume.authorLine,
      coverUrl: volume.thumbnailUrl,
    );
  }
}

void main() {
  group('OpenLibraryClient', () {
    test('turns Google-style queries into Open Library fields', () {
      expect(
        OpenLibraryClient.translate('inauthor:"Stephen King" subject:horror'),
        {'author': 'Stephen King', 'subject': 'horror'},
      );
      expect(OpenLibraryClient.translate('isbn:9781451698848'), {
        'isbn': '9781451698848',
      });
      expect(OpenLibraryClient.translate('subject:"fiction" "award winning"'), {
        'subject': 'fiction',
        'q': 'award winning',
      });
    });

    test('maps a result to a volume with an ol: id and a cover', () {
      final book = OpenLibraryClient.fromDoc(_doc())!;
      expect(book.id, 'ol:OL81634W');
      expect(book.title, 'Doctor Sleep');
      expect(book.authorLine, 'Stephen King');
      expect(book.thumbnailUrl, contains('/b/id/14652972-M.jpg'));
      expect(book.isbn13, '9781451698848');
      expect(book.isbn10, '1451698844');
      expect(book.pageCount, 531);
      expect(book.publishedDate, '2013');
      expect(book.ratingsCount, 120);
      expect(OpenLibraryClient.fromDoc(const {'title': 'no key'}), isNull);
    });

    test('caches searches and covers, misses included', () async {
      final requests = <Uri>[];
      final client = _openLibrary([_doc(cover: null)], requests);

      await client.search('doctor sleep');
      await client.search('doctor sleep');
      expect(requests, hasLength(1));

      expect(await client.coverFor(title: 'Unknown Thing'), isNull);
      expect(await client.coverFor(title: 'Unknown Thing'), isNull);
      expect(requests, hasLength(2));
    });

    test('newest sorts by publication', () async {
      final requests = <Uri>[];
      await _openLibrary([], requests).search('subject:fiction', newest: true);
      expect(requests.single.queryParameters['sort'], 'new');
    });
  });

  group('BookLookupService falls back to Open Library', () {
    late List<Uri> googleCalls;
    late List<Uri> openLibraryCalls;
    late _Cache cache;
    var now = DateTime(2026, 9, 17, 12);

    BookLookupService service({
      int googleStatus = 429,
      List<Map<String, dynamic>> docs = const [],
    }) {
      googleCalls = [];
      openLibraryCalls = [];
      cache = _Cache();
      now = DateTime(2026, 9, 17, 12);
      return BookLookupService(
        cache: cache,
        googleBooks: GoogleBooksApiClient(
          client: MockClient((request) async {
            googleCalls.add(request.url);
            return http.Response('{"error":"quota"}', googleStatus);
          }),
          authHeaders: () async => const {},
          retryDelays: const [],
        ),
        openLibrary: _openLibrary(docs, openLibraryCalls),
        clock: () => now,
      );
    }

    test('a refused Google search answers from Open Library', () async {
      final lookup = service(docs: [_doc()]);

      final results = await lookup.searchCatalogue('doctor sleep');

      expect(results.single.id, 'ol:OL81634W');
      expect(googleCalls, hasLength(1));
      expect(openLibraryCalls, hasLength(1));
    });

    test('then skips Google for a while instead of waiting on it', () async {
      final lookup = service(docs: [_doc()]);
      await lookup.searchCatalogue('doctor sleep');

      await lookup.searchCatalogue('the shining');
      expect(googleCalls, hasLength(1), reason: 'Google is resting');

      now = now.add(BookLookupService.googleCooldown);
      await lookup.searchCatalogue('it');
      expect(googleCalls, hasLength(2), reason: 'Google is tried again');
    });

    test('adding a book Google refused caches the Open Library one', () async {
      final lookup = service(docs: [_doc()]);

      final book = await lookup.findOrFetch('doctor sleep');

      expect(book.googleBooksId, 'ol:OL81634W');
      expect(cache.cached.single.thumbnailUrl, contains('14652972'));
    });

    test('a Google volume without a cover gets Open Library\'s', () async {
      final lookup = service(docs: [_doc()]);
      const volume = GoogleBook(
        id: 'gb-coverless',
        title: 'Doctor Sleep',
        authors: ['Stephen King'],
        isbn13: '9781451698848',
      );

      await lookup.resolveVolume(volume);

      expect(cache.cached.single.id, 'gb-coverless');
      expect(cache.cached.single.thumbnailUrl, contains('14652972'));
    });

    test('with no backup, Google failures still surface', () async {
      final lookup = BookLookupService(
        cache: _Cache(),
        googleBooks: GoogleBooksApiClient(
          client: MockClient((_) async => http.Response('{}', 429)),
          authHeaders: () async => const {},
          retryDelays: const [],
        ),
      );
      await expectLater(
        lookup.searchCatalogue('dune'),
        throwsA(isA<Exception>()),
      );
    });
  });
  group('BookLookupService hedges a slow Google search', () {
    BookLookupService hedged({
      required Duration googleDelay,
      required List<Uri> openLibraryCalls,
    }) => BookLookupService(
      cache: _Cache(),
      googleBooks: GoogleBooksApiClient(
        client: MockClient((request) async {
          await Future<void>.delayed(googleDelay);
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'gb-dune',
                  'volumeInfo': {
                    'title': 'Dune',
                    'authors': ['Frank Herbert'],
                  },
                },
              ],
            }),
            200,
          );
        }),
        authHeaders: () async => const {},
        retryDelays: const [],
      ),
      openLibrary: _openLibrary([_doc()], openLibraryCalls),
      hedgeAfter: const Duration(milliseconds: 20),
    );

    test('a slow Google answer loses to Open Library', () async {
      final calls = <Uri>[];
      final lookup = hedged(
        googleDelay: const Duration(milliseconds: 300),
        openLibraryCalls: calls,
      );

      final results = await lookup.searchCatalogue('doctor sleep');

      expect(results.single.id, 'ol:OL81634W');
      expect(calls, hasLength(1));
    });

    test('a quick Google answer never asks Open Library', () async {
      final calls = <Uri>[];
      final lookup = hedged(
        googleDelay: Duration.zero,
        openLibraryCalls: calls,
      );

      final results = await lookup.searchCatalogue('dune');

      expect(results.single.id, 'gb-dune');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(calls, isEmpty);
    });
  });
}
