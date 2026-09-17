import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/goals/presentation/goal_scope.dart';
import 'package:book/features/library/data/book_cache_repository.dart';
import 'package:book/features/library/data/google_books_api_client.dart';
import 'package:book/features/library/data/reading_event_repository.dart';
import 'package:book/features/library/data/user_book_repository.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/book_lookup_service.dart';
import 'package:book/features/library/domain/library_book.dart';
import 'package:book/features/library/domain/reading_event.dart';
import 'package:book/features/library/domain/user_book.dart';
import 'package:book/features/library/presentation/controllers/library_controller.dart';
import 'package:book/features/library/presentation/library_scope.dart';
import 'package:book/features/logging/presentation/first_steps_controller.dart';
import 'package:book/features/logging/presentation/pages/home_page.dart';
import 'package:book/features/memory/data/memory_repository.dart';
import 'package:book/features/memory/domain/memory.dart';
import 'package:book/features/memory/presentation/controllers/memory_controller.dart';
import 'package:book/features/memory/presentation/memory_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fake_goals.dart';

LibraryBook _book({
  int page = 0,
  ReadingStatus status = ReadingStatus.reading,
}) => LibraryBook(
  book: const Book(
    id: 'b1',
    googleBooksId: 'g1',
    title: 'Dune',
    author: 'Frank Herbert',
    pageCount: 400,
  ),
  progress: UserBook(id: 'u1', bookId: 'b1', currentPage: page, status: status),
);

class _NoCache extends BookCacheRepository {
  @override
  Future<Book?> findByGoogleBooksId(String id) async => null;
}

class _Shelf extends UserBookRepository {
  _Shelf(this.rows);

  final List<LibraryBook> rows;

  @override
  Future<List<LibraryBook>> fetchLibrary() async => rows;

  @override
  Future<DateTime?> fetchImportedAt() async => null;
}

class _Events extends ReadingEventRepository {
  @override
  Future<List<ReadingEvent>> fetchForYear(int year) async => const [];
}

class _NoMemories extends MemoryRepository {
  @override
  Future<List<Memory>> fetchAll() async => const [];
}

void main() {
  tearDown(FirstStepsController.reset);

  group('FirstSteps.done', () {
    test('nothing on a new shelf', () {
      expect(FirstSteps.done(books: const [], goal: null), isEmpty);
    });

    test('follows the shelf and the goal', () {
      expect(FirstSteps.done(books: [_book()], goal: null), {
        FirstStep.addBook,
      });
      expect(FirstSteps.done(books: [_book(page: 12)], goal: 20), {
        FirstStep.addBook,
        FirstStep.logPage,
        FirstStep.setGoal,
      });
      expect(
        FirstSteps.done(
          books: [_book(page: 400, status: ReadingStatus.finished)],
          goal: 20,
        ),
        FirstStep.values.toSet(),
      );
    });
  });

  Future<void> pumpHome(
    WidgetTester tester, {
    List<LibraryBook> rows = const [],
    VoidCallback? onOpenSearch,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final library = LibraryController(
      lookup: BookLookupService(
        cache: _NoCache(),
        googleBooks: GoogleBooksApiClient(
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
      ),
      userBooks: _Shelf(rows),
      events: _Events(),
    );
    final memory = MemoryController(repository: _NoMemories());
    addTearDown(library.dispose);
    addTearDown(memory.dispose);
    await library.load();

    await tester.pumpWidget(
      GoalScope(
        controller: goalControllerFor(),
        child: LibraryScope(
          controller: library,
          child: MemoryScope(
            controller: memory,
            child: MaterialApp(
              theme: AppTheme.light,
              home: HomePage(onOpenSearch: onOpenSearch),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('hidden unless turned on — as in every other test', (
    tester,
  ) async {
    await pumpHome(tester);
    expect(find.byKey(const ValueKey('first-steps')), findsNothing);
  });

  testWidgets('a new reader is shown the next tap', (tester) async {
    FirstStepsController.reset(visible: true);
    var openedSearch = 0;
    await pumpHome(tester, onOpenSearch: () => openedSearch++);

    expect(find.text('first steps · 0 of 4'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('first-step-addBook')));
    expect(openedSearch, 1);
  });

  testWidgets('ticks off what is done, and can be hidden', (tester) async {
    FirstStepsController.reset(visible: true);
    await pumpHome(tester, rows: [_book(page: 12)]);

    expect(find.text('first steps · 2 of 4'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('first-steps-dismiss')));
    await tester.pump();
    expect(find.byKey(const ValueKey('first-steps')), findsNothing);
    expect(FirstStepsController.visible.value, isFalse);
  });
}
