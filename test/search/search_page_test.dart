import 'dart:convert';

import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/library/data/book_cache_repository.dart';
import 'package:book/features/library/data/google_book.dart';
import 'package:book/features/library/data/google_books_api_client.dart';
import 'package:book/features/library/data/user_book_repository.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/book_lookup_service.dart';
import 'package:book/features/library/domain/library_book.dart';
import 'package:book/features/library/domain/user_book.dart';
import 'package:book/features/library/presentation/controllers/library_controller.dart';
import 'package:book/features/library/presentation/library_scope.dart';
import 'package:book/features/library/presentation/pages/book_detail_page.dart';
import 'package:book/features/search/domain/reading_taste.dart';
import 'package:book/features/search/domain/recommendation_seeds.dart';
import 'package:book/features/search/presentation/pages/search_page.dart';
import 'package:book/features/search/presentation/pages/volume_detail_page.dart';
import 'package:book/features/search/presentation/widgets/book_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _dune = Book(
  id: 'book-1',
  googleBooksId: 'gb-dune',
  title: 'Dune',
  author: 'Frank Herbert',
  pageCount: 400,
);

LibraryBook _entry(
  Book book, {
  String id = 'progress-1',
  ReadingStatus status = ReadingStatus.reading,
}) => LibraryBook(
  book: book,
  progress: UserBook(id: id, bookId: book.id, currentPage: 0, status: status),
);

Map<String, dynamic> _volume(String id, String title, String author) => {
  'id': id,
  'volumeInfo': {
    'title': title,
    'authors': [author],
    'publishedDate': '1969-05-01',
    'pageCount': 300,
  },
};

/// Answers every Google Books search with a fixed set of volumes, and
/// records each query.
MockClient _google(List<Map<String, dynamic>> volumes, List<String> queries) =>
    MockClient((request) async {
      queries.add(request.url.queryParameters['q'] ?? '');
      return http.Response(jsonEncode({'items': volumes}), 200);
    });

class _Shelf extends UserBookRepository {
  _Shelf(this.rows);

  final List<LibraryBook> rows;
  final added = <(String, ReadingStatus)>[];

  @override
  Future<List<LibraryBook>> fetchLibrary() async => List.of(rows);

  @override
  Future<StartOutcome> addWithStatus(
    String bookId,
    ReadingStatus status, {
    int currentPage = 0,
    String? shelfId,
    DateTime? startedAt,
    DateTime? finishedAt,
  }) async {
    added.add((bookId, status));
    return StartOutcome(
      UserBook(
        id: 'progress-$bookId',
        bookId: bookId,
        currentPage: currentPage,
        status: status,
      ),
      alreadyExists: false,
    );
  }
}

class _Cache extends BookCacheRepository {
  @override
  Future<Book?> findByTitle(String title, {String? author}) async => null;
  @override
  Future<Book?> findByGoogleBooksId(String id) async => null;
  @override
  Future<Book> cache(GoogleBook volume) async => Book(
    id: 'book-${volume.id}',
    googleBooksId: volume.id,
    title: volume.title,
    author: volume.authorLine,
    pageCount: volume.pageCount,
  );
}

void main() {
  late _Shelf shelf;
  late List<String> queries;

  Future<LibraryController> pumpSearch(
    WidgetTester tester, {
    List<LibraryBook> rows = const [],
    List<Map<String, dynamic>> volumes = const [],
    Widget? home,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    queries = [];
    shelf = _Shelf(rows);
    final controller = LibraryController(
      lookup: BookLookupService(
        cache: _Cache(),
        googleBooks: GoogleBooksApiClient(
          client: _google(volumes, queries),
          authHeaders: () async => const {},
        ),
      ),
      userBooks: shelf,
    );
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      LibraryScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: home ?? const SearchPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('search-field')), text);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
  }

  group('recommendations', () {
    test('come from the author being read, then the top genre', () {
      final seeds = RecommendationSeeds.from([
        _entry(_dune),
        _entry(
          const Book(
            id: 'book-2',
            googleBooksId: 'gb-2',
            title: 'Foundation',
            author: 'Isaac Asimov',
            categories: ['Fiction / Science Fiction / General'],
          ),
          id: 'progress-2',
          status: ReadingStatus.finished,
        ),
      ]);

      expect(seeds.first.label, 'more by Frank Herbert');
      expect(seeds.first.query, 'inauthor:"Frank Herbert"');
      expect(seeds, hasLength(2));
      expect(seeds.last.label, startsWith('more in '));
    });

    test('tastes add a row each, and stand in for classics', () {
      final seeds = RecommendationSeeds.from(
        const [],
        tastes: [ReadingTaste.fantasy, ReadingTaste.mystery],
      );
      expect(seeds.map((s) => s.label), [
        'fantasy for you',
        'mystery & thriller for you',
      ]);
      expect(seeds.first.query, 'subject:"fantasy"');
    });

    test('an empty shelf starts with classics', () {
      expect(
        RecommendationSeeds.from(const []).single.label,
        'classics to start with',
      );
    });

    testWidgets('show under an empty search bar, without books already '
        'on the shelf', (tester) async {
      await pumpSearch(
        tester,
        rows: [_entry(_dune)],
        volumes: [
          _volume('gb-dune', 'Dune', 'Frank Herbert'),
          _volume('gb-messiah', 'Dune Messiah', 'Frank Herbert'),
        ],
      );

      expect(find.text('more by Frank Herbert'), findsOneWidget);
      expect(queries, contains('inauthor:"Frank Herbert"'));
      expect(
        find.byKey(const ValueKey('recommended-gb-messiah')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('recommended-gb-dune')), findsNothing);
    });
  });

  group('searching', () {
    testWidgets('shows shelf matches first, then Google Books results', (
      tester,
    ) async {
      await pumpSearch(
        tester,
        rows: [_entry(_dune)],
        volumes: [
          _volume('gb-dune', 'Dune', 'Frank Herbert'),
          _volume('gb-children', 'Children of Dune', 'Frank Herbert'),
        ],
      );

      await type(tester, 'dune');

      expect(find.text('on your shelf'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('search-shelf-progress-1')),
        findsOneWidget,
      );
      expect(find.text('google books'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('search-volume-gb-children')),
        findsOneWidget,
      );
      // The one already on the shelf isn't offered twice.
      expect(find.byKey(const ValueKey('search-volume-gb-dune')), findsNothing);
      expect(
        tester.getTopLeft(find.text('on your shelf')).dy,
        lessThan(tester.getTopLeft(find.text('google books')).dy),
      );
    });

    testWidgets('the + adds a result to read in one tap', (tester) async {
      final controller = await pumpSearch(
        tester,
        volumes: [_volume('gb-hobbit', 'The Hobbit', 'J.R.R. Tolkien')],
      );

      await type(tester, 'hobbit');
      await tester.tap(find.byKey(const ValueKey('search-add-gb-hobbit')));
      await tester.pumpAndSettle();

      expect(shelf.added, [('book-gb-hobbit', ReadingStatus.toBeRead)]);
      expect(controller.toBeRead.single.book.title, 'The Hobbit');
      expect(find.text('Added "The Hobbit" to read'), findsOneWidget);
    });

    testWidgets('tapping a result previews it, with want to read and the '
        'other shelves', (tester) async {
      final controller = await pumpSearch(
        tester,
        volumes: [_volume('gb-hobbit', 'The Hobbit', 'J.R.R. Tolkien')],
      );

      await type(tester, 'hobbit');
      await tester.tap(find.byKey(const ValueKey('search-volume-gb-hobbit')));
      await tester.pumpAndSettle();

      expect(find.text('want to read'), findsOneWidget);
      expect(find.text('1969 · 300 pages'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('preview-finished')));
      await tester.pumpAndSettle();

      expect(controller.finished.single.book.title, 'The Hobbit');
      expect(controller.finished.single.currentPage, 300);
    });

    testWidgets('see all details opens the Google Books page, which can add '
        'the book too', (tester) async {
      final controller = await pumpSearch(
        tester,
        volumes: [_volume('gb-hobbit', 'The Hobbit', 'J.R.R. Tolkien')],
      );

      await type(tester, 'hobbit');
      await tester.tap(find.byKey(const ValueKey('search-volume-gb-hobbit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('preview-details')));
      await tester.pumpAndSettle();

      expect(find.byType(VolumeDetailPage), findsOneWidget);
      expect(find.text('from google books'), findsOneWidget);
      expect(find.text('The Hobbit'), findsWidgets);
      expect(find.text('300'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('preview-want-to-read')));
      await tester.pumpAndSettle();

      expect(controller.toBeRead.single.book.title, 'The Hobbit');
      expect(find.text('open book'), findsOneWidget);
    });

    testWidgets('says so when nothing matches anywhere', (tester) async {
      await pumpSearch(tester);

      await type(tester, 'zzzz');

      expect(find.text('no books match "zzzz".'), findsOneWidget);
    });

    testWidgets('tapping a shelf match opens its book page', (tester) async {
      await pumpSearch(tester, rows: [_entry(_dune)]);

      await type(tester, 'herbert');
      await tester.tap(find.byKey(const ValueKey('search-shelf-progress-1')));
      await tester.pumpAndSettle();

      expect(find.byType(BookDetailPage), findsOneWidget);
    });
  });

  group('book picker', () {
    Future<List<BookPick?>> pumpPicker(
      WidgetTester tester, {
      List<LibraryBook> rows = const [],
      List<Map<String, dynamic>> volumes = const [],
      String query = '',
    }) async {
      final picks = <BookPick?>[];
      await pumpSearch(
        tester,
        rows: rows,
        volumes: volumes,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  picks.add(await showBookPicker(context, query: query)),
              child: const Text('open picker'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open picker'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      return picks;
    }

    testWidgets('picks a book from the library', (tester) async {
      final picks = await pumpPicker(
        tester,
        rows: [_entry(_dune)],
        query: 'dune',
      );

      expect(find.text('which book?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('picker-shelf-progress-1')));
      await tester.pumpAndSettle();

      expect((picks.single! as ShelfPick).entry.id, 'progress-1');
    });

    testWidgets('picks a book from Google Books', (tester) async {
      final picks = await pumpPicker(
        tester,
        volumes: [
          _volume(
            'gb-potter',
            "Harry Potter and the Philosopher's "
                'Stone',
            'J.K. Rowling',
          ),
        ],
        query: 'harry potter',
      );

      await tester.tap(find.byKey(const ValueKey('book-picker-google')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('picker-volume-gb-potter')));
      await tester.pumpAndSettle();

      expect((picks.single! as CataloguePick).volume.id, 'gb-potter');
    });
  });
}
