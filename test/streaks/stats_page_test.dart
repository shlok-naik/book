import 'package:book/core/purchases/entitlements.dart';
import 'package:book/core/purchases/purchases_service.dart';
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
import 'package:book/features/paywall/presentation/pages/paywall_page.dart';
import 'package:book/features/streaks/presentation/pages/stats_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../support/fake_goals.dart';

class _FakePurchasesService extends PurchasesService {
  _FakePurchasesService({required this.info});

  final CustomerInfo info;

  @override
  Future<CustomerInfo> get customerInfo async => info;
}

CustomerInfo _customerInfo({required bool pro}) {
  final entitlements = pro
      ? {
          Entitlements.cactusPro: const EntitlementInfo(
            Entitlements.cactusPro,
            true,
            true,
            '2024-01-01T00:00:00Z',
            '2024-01-01T00:00:00Z',
            'yearly',
            false,
          ),
        }
      : const <String, EntitlementInfo>{};
  return CustomerInfo(
    EntitlementInfos(entitlements, entitlements),
    const {},
    const [],
    const [],
    const [],
    '2024-01-01T00:00:00Z',
    'fake-user-id',
    const {},
    '2024-01-01T00:00:00Z',
  );
}

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
  PurchasesService? purchases,
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
        child: MaterialApp(
          theme: AppTheme.light,
          // Pro by default — what the journal itself renders is what
          // most of this file is testing, and that's only reachable
          // once it's unlocked. The `pro gate` group below covers the
          // locked state on its own.
          home: StatsPage(
            purchases:
                purchases ??
                _FakePurchasesService(info: _customerInfo(pro: true)),
          ),
        ),
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

  testWidgets(
    'without a goal, says so — the goal is not editable from this page',
    (tester) async {
      await pumpJournal(tester, []);

      expect(find.text('no reading goal set yet'), findsOneWidget);
      // No "set a reading goal" prompt, no edit icon, and nothing to tap —
      // a goal is only ever changed from settings.
      expect(find.text('set a reading goal'), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    },
  );

  testWidgets('a set goal shows its progress, still without an edit icon', (
    tester,
  ) async {
    await pumpJournal(tester, [], goal: 24);

    expect(find.text(' / 24 books'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });

  group('charts', () {
    final year = DateTime.now().year;

    testWidgets('an empty shelf shows every chart\'s own empty-state line', (
      tester,
    ) async {
      await pumpJournal(tester, []);

      expect(find.text('books per month'), findsOneWidget);
      expect(find.text('nothing finished in $year yet.'), findsOneWidget);
      expect(find.text('pages per month'), findsOneWidget);
      expect(find.text('no pages logged in $year yet.'), findsOneWidget);
      expect(find.text('pace'), findsOneWidget);
      expect(
        find.text('finish a book to start tracking your pace.'),
        findsOneWidget,
      );
      expect(find.text('your shelf'), findsOneWidget);
      expect(find.text('nothing on your shelf yet.'), findsOneWidget);
    });

    testWidgets(
      'a shelf with books draws the shelf donut and the pace legend',
      (tester) async {
        await pumpJournal(
          tester,
          [],
          goal: 12,
          books: [
            LibraryBook(
              book: const Book(
                id: 'b1',
                googleBooksId: 'g1',
                title: 'Dune',
                author: 'Frank Herbert',
                pageCount: 400,
              ),
              progress: UserBook(
                id: 'u1',
                bookId: 'b1',
                currentPage: 400,
                status: ReadingStatus.finished,
                finishedAt: DateTime(year, 2, 1),
              ),
            ),
            const LibraryBook(
              book: Book(
                id: 'b2',
                googleBooksId: 'g2',
                title: 'Dune Messiah',
                author: 'Frank Herbert',
              ),
              progress: UserBook(
                id: 'u2',
                bookId: 'b2',
                currentPage: 50,
                status: ReadingStatus.reading,
              ),
            ),
            const LibraryBook(
              book: Book(
                id: 'b3',
                googleBooksId: 'g3',
                title: 'Children of Dune',
                author: 'Frank Herbert',
              ),
              progress: UserBook(
                id: 'u3',
                bookId: 'b3',
                currentPage: 0,
                status: ReadingStatus.toBeRead,
              ),
            ),
          ],
        );

        // No more empty-state fallbacks once there's something to chart.
        expect(find.text('nothing finished in $year yet.'), findsNothing);
        expect(find.text('nothing on your shelf yet.'), findsNothing);

        // The donut legend names every non-empty shelf, with counts.
        expect(find.text('reading'), findsOneWidget);
        expect(find.text('to read'), findsOneWidget);
        expect(find.text('finished'), findsOneWidget);
        expect(find.text('did not finish'), findsNothing);
        expect(find.text('3'), findsOneWidget); // the donut's own total

        // The pace chart only shows its comparison legend once a goal exists.
        expect(find.text('you'), findsOneWidget);
        expect(find.text('steady pace'), findsOneWidget);
      },
    );
  });

  group('pro gate', () {
    const cta = 'cactus pro unlocks your full reading journal — tap to upgrade';

    testWidgets('a free reader sees a locked preview, not the real journal', (
      tester,
    ) async {
      await pumpJournal(tester, [
        ReadingEvent(
          type: ReadingEventType.start,
          occurredAt: DateTime.utc(2026, 1, 1),
          title: 'Neuromancer',
        ),
      ], purchases: _FakePurchasesService(info: _customerInfo(pro: false)));

      expect(find.text('journal'), findsOneWidget);
      expect(find.text(cta), findsOneWidget);
      expect(find.textContaining('Neuromancer'), findsNothing);
      expect(find.text('started The Hobbit'), findsOneWidget);
    });

    testWidgets('a pro reader sees the real journal, not the locked preview', (
      tester,
    ) async {
      await pumpJournal(tester, [
        ReadingEvent(
          type: ReadingEventType.start,
          occurredAt: DateTime.utc(2026, 1, 1),
          title: 'Neuromancer',
        ),
      ], purchases: _FakePurchasesService(info: _customerInfo(pro: true)));

      expect(find.text('started Neuromancer'), findsOneWidget);
      expect(find.text(cta), findsNothing);
      expect(find.text('started The Hobbit'), findsNothing);
    });

    testWidgets('tapping the locked journal reaches the paywall', (
      tester,
    ) async {
      await pumpJournal(
        tester,
        [],
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
      );

      final row = find.text(cta);
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(find.byType(PaywallPage), findsOneWidget);
    });
  });
}
