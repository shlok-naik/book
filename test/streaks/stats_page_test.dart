import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/goals/presentation/controllers/goal_controller.dart';
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
import 'package:book/features/streaks/presentation/pages/stats_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fake_goals.dart';

/// The streak page as a journal: every logged command rendered back as
/// text, grouped under the day it happened. What matters here is the
/// exact wording and the date label, not the data layer underneath —
/// that's `streaks_controller_test.dart`'s job.

class _EmptyCache extends BookCacheRepository {
  @override
  Future<Book?> findByTitle(String title, {String? author}) async => null;

  @override
  Future<Book?> findByGoogleBooksId(String id) async => null;
}

class _EmptyUserBooks extends UserBookRepository {
  _EmptyUserBooks([this.rows = const []]);

  final List<LibraryBook> rows;

  @override
  Future<List<LibraryBook>> fetchLibrary() async => rows;
}

class _FakeReadingEventRepository extends ReadingEventRepository {
  _FakeReadingEventRepository(this.rows);

  final List<ReadingEvent> rows;

  @override
  Future<List<ReadingEvent>> fetchForYear(int year) async => List.of(rows);
}

LibraryController _controller(
  List<ReadingEvent> rows, [
  List<LibraryBook> books = const [],
]) {
  return LibraryController(
    lookup: BookLookupService(
      cache: _EmptyCache(),
      googleBooks: GoogleBooksApiClient(
        client: MockClient((_) async => http.Response('unused', 200)),
      ),
    ),
    userBooks: _EmptyUserBooks(books),
    events: _FakeReadingEventRepository(rows),
  );
}

Future<GoalController> pumpJournal(
  WidgetTester tester,
  List<ReadingEvent> rows, {
  List<LibraryBook> books = const [],
  int? goal,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final controller = _controller(rows, books);
  addTearDown(controller.dispose);
  await controller.load();
  final goals = goalControllerFor(goal: goal);

  await tester.pumpWidget(
    GoalScope(
      controller: goals,
      child: LibraryScope(
        controller: controller,
        child: MaterialApp(theme: AppTheme.light, home: const StatsPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return goals;
}

void main() {
  testWidgets('reads a day\'s commands back exactly as they were typed', (
    tester,
  ) async {
    final day = DateTime.utc(2026, 3, 12, 9);
    await pumpJournal(tester, [
      ReadingEvent(
        type: ReadingEventType.start,
        occurredAt: day,
        title: 'Dune',
      ),
      ReadingEvent(
        type: ReadingEventType.update,
        occurredAt: day.add(const Duration(hours: 2)),
        title: 'Dune',
        value: 120,
      ),
      ReadingEvent(
        type: ReadingEventType.finish,
        occurredAt: day.add(const Duration(hours: 4)),
        title: 'Dune',
      ),
      ReadingEvent(
        type: ReadingEventType.rate,
        occurredAt: day.add(const Duration(hours: 5)),
        title: 'Dune',
        value: 4.5,
      ),
    ]);

    expect(find.text('3.12.26'), findsOneWidget);
    expect(find.text('started Dune'), findsOneWidget);
    expect(find.text('read up to page 120 in Dune'), findsOneWidget);
    expect(find.text('finished Dune'), findsOneWidget);
    expect(find.text('rated Dune 4.5 stars'), findsOneWidget);
  });

  testWidgets('a single star reads in the singular', (tester) async {
    await pumpJournal(tester, [
      ReadingEvent(
        type: ReadingEventType.rate,
        occurredAt: DateTime.utc(2026, 1, 1),
        title: 'Neuromancer',
        value: 1,
      ),
    ]);

    expect(find.text('rated Neuromancer 1 star'), findsOneWidget);
  });

  testWidgets('a deleted book leaves no line behind', (tester) async {
    await pumpJournal(tester, [
      ReadingEvent(
        type: ReadingEventType.delete,
        occurredAt: DateTime.utc(2026, 1, 1),
        title: 'Neuromancer',
      ),
    ]);

    expect(find.textContaining('Neuromancer'), findsNothing);
    expect(find.text('nothing logged yet — start a book.'), findsOneWidget);
  });

  testWidgets('says so when nothing has ever been logged', (tester) async {
    await pumpJournal(tester, []);

    expect(find.text('nothing logged yet — start a book.'), findsOneWidget);
  });

  testWidgets('leads with the reading goal, then the shelf numbers', (
    tester,
  ) async {
    final year = DateTime.now().year;
    await pumpJournal(
      tester,
      [],
      goal: 10,
      books: [
        LibraryBook(
          book: const Book(
            id: 'b1',
            googleBooksId: 'g1',
            title: 'Dune',
            author: 'Frank Herbert',
            pageCount: 400,
            categories: ['Fiction / Science Fiction'],
          ),
          progress: UserBook(
            id: 'u1',
            bookId: 'b1',
            currentPage: 400,
            status: ReadingStatus.finished,
            finishedAt: DateTime(year, 1, 2),
          ),
        ),
      ],
    );

    expect(find.text('1'), findsWidgets);
    expect(find.text(' / 10 books'), findsOneWidget);
    expect(find.text('books read'), findsOneWidget);
    expect(find.text('pages read'), findsOneWidget);
    expect(find.text('400'), findsOneWidget);
    expect(find.text('science fiction'), findsOneWidget);
    // The goal is above the tiles, which are above the journal.
    final goalY = tester.getTopLeft(find.text(' / 10 books')).dy;
    final tilesY = tester.getTopLeft(find.text('books read')).dy;
    final journalY = tester.getTopLeft(find.text('journal')).dy;
    expect(goalY, lessThan(tilesY));
    expect(tilesY, lessThan(journalY));
  });

  testWidgets('without a goal, offers to set one — and saving it shows it', (
    tester,
  ) async {
    final goals = await pumpJournal(tester, []);

    await tester.tap(find.text('set a reading goal'));
    await tester.pumpAndSettle();
    expect(find.text('reading goal'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('24'));
    await tester.pump();
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();

    expect(goals.goal, 24);
    expect(find.text(' / 24 books'), findsOneWidget);
  });
}
