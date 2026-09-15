import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/library/data/book_cache_repository.dart';
import 'package:book/features/library/data/book_series_repository.dart';
import 'package:book/features/library/data/google_book.dart';
import 'package:book/features/library/data/google_books_api_client.dart';
import 'package:book/features/library/data/user_book_repository.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/book_lookup_service.dart';
import 'package:book/features/library/domain/book_series.dart';
import 'package:book/features/library/domain/library_book.dart';
import 'package:book/features/library/domain/library_exception.dart';
import 'package:book/features/library/domain/user_book.dart';
import 'package:book/features/library/presentation/controllers/library_controller.dart';
import 'package:book/features/library/presentation/library_scope.dart';
import 'package:book/features/library/presentation/widgets/series_selection_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fake_collections.dart';

class _Shelf extends UserBookRepository {
  @override
  Future<List<LibraryBook>> fetchLibrary() async => [
    const LibraryBook(
      book: Book(id: 'b1', googleBooksId: 'g1', title: 'Dune', author: 'FH'),
      progress: UserBook(
        id: 'u1',
        bookId: 'b1',
        currentPage: 0,
        status: ReadingStatus.reading,
      ),
    ),
  ];

  @override
  Future<DateTime?> fetchImportedAt() async => null;
}

class _ManySeries extends BookSeriesRepository {
  @override
  Future<List<BookSeries>> fetchMySeries() async => [
    for (var i = 1; i <= 30; i++) BookSeries(id: 's$i', name: 'series $i'),
  ];
}

class _Cache extends BookCacheRepository {
  @override
  Future<Book?> findByTitle(String title, {String? author}) async => null;
  @override
  Future<Book?> findByGoogleBooksId(String id) async => null;
  @override
  Future<Book> cache(GoogleBook volume) async =>
      throw const RemoteDataException('unused');
}

void main() {
  // Regression: one Column row per series overflowed the sheet, and the
  // lower series could not be reached.
  testWidgets('a long series list scrolls to its last series', (tester) async {
    final overflows = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) {
        overflows.add(details.exceptionAsString());
      } else {
        previous?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = previous);

    final library = LibraryController(
      lookup: BookLookupService(
        cache: _Cache(),
        googleBooks: GoogleBooksApiClient(
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
      ),
      userBooks: _Shelf(),
      series: _ManySeries(),
      collections: FakeCollectionsRepository(),
    );
    addTearDown(library.dispose);
    await library.load();

    await tester.pumpWidget(
      LibraryScope(
        controller: library,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showSeriesSelectionSheet(context, 'u1'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('series 30'),
      200,
      // The list's own scrollable — not the #n fields' inner ones.
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('series 30'), findsOneWidget);
    expect(overflows, isEmpty);
  });
}
