import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/library/data/google_books_api_client.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/book_lookup_service.dart';
import 'package:book/features/library/domain/library_book.dart';
import 'package:book/features/library/domain/user_book.dart';
import 'package:book/features/library/presentation/controllers/library_controller.dart';
import 'package:book/features/library/presentation/library_scope.dart';
import 'package:book/features/library/presentation/pages/book_detail_page.dart';
import 'package:book/features/search/presentation/pages/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../library/library_page_test.dart'
    show StubUserBookRepository, UnusedCache;

LibraryBook _entry(String id, String title, String author) => LibraryBook(
  book: Book(id: id, googleBooksId: 'gb-$id', title: title, author: author),
  progress: UserBook(
    id: 'progress-$id',
    bookId: id,
    currentPage: 0,
    status: ReadingStatus.reading,
  ),
);

void main() {
  Future<LibraryController> pumpSearch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = LibraryController(
      lookup: BookLookupService(
        cache: UnusedCache(),
        googleBooks: GoogleBooksApiClient(
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
      ),
      userBooks: StubUserBookRepository([
        _entry('1', 'Dune', 'Frank Herbert'),
        _entry('2', 'Pale Fire', 'Vladimir Nabokov'),
      ]),
    );
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      LibraryScope(
        controller: controller,
        child: MaterialApp(theme: AppTheme.light, home: const SearchPage()),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('shows nothing until something is typed', (tester) async {
    await pumpSearch(tester);

    expect(find.text('search'), findsOneWidget);
    expect(find.text('Dune'), findsNothing);
  });

  testWidgets('finds shelf books by title or author', (tester) async {
    await pumpSearch(tester);

    await tester.enterText(find.byKey(const ValueKey('search-field')), 'nabo');
    await tester.pumpAndSettle();

    expect(find.text('Pale Fire'), findsOneWidget);
    expect(find.text('Dune'), findsNothing);
  });

  testWidgets('says so when nothing on the shelf matches', (tester) async {
    await pumpSearch(tester);

    await tester.enterText(
      find.byKey(const ValueKey('search-field')),
      'hobbit',
    );
    await tester.pumpAndSettle();

    expect(find.text('no books on your shelf match "hobbit"'), findsOneWidget);
  });

  testWidgets('tapping a result opens its book page', (tester) async {
    await pumpSearch(tester);

    await tester.enterText(find.byKey(const ValueKey('search-field')), 'dune');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dune'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(BookDetailPage), findsOneWidget);
  });
}
