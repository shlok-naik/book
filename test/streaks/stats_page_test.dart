import 'package:book/core/purchases/entitlements.dart';
import 'package:book/core/purchases/purchases_service.dart';
import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/goals/presentation/controllers/goal_controller.dart';
import 'package:book/features/goals/presentation/goal_scope.dart';
import 'package:book/features/library/data/book_cache_repository.dart';
import 'package:book/features/library/data/book_notes_repository.dart';
import 'package:book/features/library/data/google_books_api_client.dart';
import 'package:book/features/library/data/reading_event_repository.dart';
import 'package:book/features/library/data/user_book_repository.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/book_lookup_service.dart';
import 'package:book/features/library/domain/book_note.dart';
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
  _EmptyUserBooks([this.rows = const [], this.importedAt]);

  final List<LibraryBook> rows;
  final DateTime? importedAt;

  @override
  Future<List<LibraryBook>> fetchLibrary() async => rows;

  @override
  Future<DateTime?> fetchImportedAt() async => importedAt;
}

class _FakeReadingEventRepository extends ReadingEventRepository {
  _FakeReadingEventRepository(this.rows);

  final List<ReadingEvent> rows;

  @override
  Future<List<ReadingEvent>> fetchForYear(int year) async => List.of(rows);
}

/// Tags for the stats page's pro "tags" section — every `book_tags` row.
class _FakeNotes extends BookNotesRepository {
  _FakeNotes([this.tags = const []]);

  final List<BookTag> tags;

  @override
  Future<List<BookTag>> fetchAllTags() async => tags;
}

LibraryController _controller(
  List<ReadingEvent> rows, [
  List<LibraryBook> books = const [],
  List<BookTag> tags = const [],
  DateTime? importedAt,
]) {
  return LibraryController(
    notes: _FakeNotes(tags),
    lookup: BookLookupService(
      cache: _EmptyCache(),
      googleBooks: GoogleBooksApiClient(
        client: MockClient((_) async => http.Response('unused', 200)),
      ),
    ),
    userBooks: _EmptyUserBooks(books, importedAt),
    events: _FakeReadingEventRepository(rows),
  );
}

Future<GoalController> pumpJournal(
  WidgetTester tester,
  List<ReadingEvent> rows, {
  List<LibraryBook> books = const [],
  List<BookTag> tags = const [],
  int? goal,
  PurchasesService? purchases,
  DateTime? importedAt,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final controller = _controller(rows, books, tags, importedAt);
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
    // The goal is above the tiles, which are above the reading days.
    final goalY = tester.getTopLeft(find.text(' / 10 books')).dy;
    final tilesY = tester.getTopLeft(find.text('books read')).dy;
    final daysY = tester.getTopLeft(find.text('reading days')).dy;
    expect(goalY, lessThan(tilesY));
    expect(tilesY, lessThan(daysY));
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
      expect(find.text('no books read in $year yet.'), findsOneWidget);
      expect(find.text('your shelf'), findsOneWidget);
      expect(find.text('nothing on your shelf yet.'), findsOneWidget);
      expect(find.text('reading days'), findsOneWidget);
      expect(find.text('nothing logged in $year yet.'), findsOneWidget);
      expect(find.text('tags'), findsOneWidget);
      expect(
        find.text('no tagged books yet — try add tag <tag> <book>.'),
        findsOneWidget,
      );
    });

    testWidgets('pace is only text, never a chart, until a book is finished '
        '— even with a goal set', (tester) async {
      await pumpJournal(tester, [], goal: 12);

      expect(find.text('no books read in $year yet.'), findsOneWidget);
      // The chart's legend is how a drawn pace chart shows up.
      expect(find.text('steady pace'), findsNothing);
      expect(find.text('you'), findsNothing);
    });

    testWidgets('reading days sums up the year above the heatmap', (
      tester,
    ) async {
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      await pumpJournal(tester, [
        ReadingEvent(
          type: ReadingEventType.start,
          occurredAt: today.toUtc(),
          title: 'Dune',
        ),
        ReadingEvent(
          type: ReadingEventType.update,
          occurredAt: today.toUtc(),
          title: 'Dune',
          value: 40,
        ),
        // A delete isn't a reading day.
        ReadingEvent(
          type: ReadingEventType.delete,
          occurredAt: yesterday.toUtc(),
          title: 'Emma',
        ),
      ]);

      expect(
        find.bySemanticsLabel(RegExp(r'^Reading days: 1 in ')),
        findsOneWidget,
      );
    });

    testWidgets('tags counts the books carrying each tag', (tester) async {
      LibraryBook onShelf(String id, String title) => LibraryBook(
        book: Book(
          id: 'b$id',
          googleBooksId: 'g$id',
          title: title,
          author: 'Someone',
        ),
        progress: UserBook(
          id: 'u$id',
          bookId: 'b$id',
          currentPage: 0,
          status: ReadingStatus.reading,
        ),
      );
      BookTag tag(String id, String userBookId, String name) => BookTag(
        id: id,
        userBookId: userBookId,
        tag: name,
        createdAt: DateTime.utc(2026, 1, 1),
      );

      await pumpJournal(
        tester,
        [],
        books: [onShelf('1', 'Dune'), onShelf('2', 'Emma')],
        tags: [
          tag('t1', 'u1', 'favourites'),
          tag('t2', 'u2', 'favourites'),
          tag('t3', 'u1', 'sci-fi'),
          // A book no longer on the shelf doesn't count.
          tag('t4', 'gone', 'sci-fi'),
        ],
      );

      expect(find.bySemanticsLabel('favourites: 2 books'), findsOneWidget);
      expect(find.bySemanticsLabel('sci-fi: 1 book'), findsOneWidget);
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

  group('import baseline', () {
    testWidgets('after an import this year, pace draws from the import with a '
        'baseline line, and monthly charts leave the imported books out', (
      tester,
    ) async {
      final year = DateTime.now().year;
      final importedAt = DateTime(year, 1, 1, 12);
      LibraryBook book(
        String id,
        DateTime finishedAt, {
        bool imported = false,
      }) => LibraryBook(
        book: Book(
          id: 'b$id',
          googleBooksId: 'g$id',
          title: 'Book $id',
          author: 'Someone',
          pageCount: 100,
        ),
        progress: UserBook(
          id: 'u$id',
          bookId: 'b$id',
          currentPage: 100,
          status: ReadingStatus.finished,
          finishedAt: finishedAt,
          imported: imported,
        ),
      );

      await pumpJournal(
        tester,
        [],
        goal: 20,
        importedAt: importedAt,
        books: [
          book('1', DateTime(year, 1, 1, 8), imported: true),
          book('2', DateTime(year, 1, 1, 9), imported: true),
          book('3', DateTime(year, 1, 1, 18)),
        ],
      );

      final label = 'imported 1.1 · 2';
      await tester.scrollUntilVisible(
        find.text(label),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(label), findsOneWidget);
      expect(find.text('steady pace'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Books finished per month in \d+: Jan 1,'),
        ),
        findsOneWidget,
        reason: 'only the book finished after the import is charted',
      );
    });
  });

  // Regression: the pace legend was a Row, and on a narrow phone
  // "you · steady pace … 3 behind" ran off the right edge.
  testWidgets('the pace legend wraps instead of overflowing a narrow phone', (
    tester,
  ) async {
    final year = DateTime.now().year;
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

    await pumpJournal(
      tester,
      [],
      goal: 40,
      books: [
        for (var i = 1; i <= 3; i++)
          LibraryBook(
            book: Book(
              id: 'b$i',
              googleBooksId: 'g$i',
              title: 'Book $i',
              author: 'Someone',
              pageCount: 100,
            ),
            progress: UserBook(
              id: 'u$i',
              bookId: 'b$i',
              currentPage: 100,
              status: ReadingStatus.finished,
              finishedAt: DateTime(year, 1, i),
            ),
          ),
      ],
    );
    // A 320-wide phone, then let the page lay out again.
    tester.view.physicalSize = const Size(640, 1400);
    tester.view.devicePixelRatio = 2;
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('steady pace'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('steady pace'), findsOneWidget);
    expect(overflows, isEmpty);
  });

  group('pro gate', () {
    testWidgets('there is no journal any more, on either plan', (tester) async {
      await pumpJournal(tester, [
        ReadingEvent(
          type: ReadingEventType.start,
          occurredAt: DateTime.utc(2026, 1, 1),
          title: 'Neuromancer',
        ),
      ]);
      expect(find.text('journal'), findsNothing);
      expect(find.text('started Neuromancer'), findsNothing);

      await pumpJournal(
        tester,
        [],
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
      );
      expect(find.text('journal'), findsNothing);
      expect(find.textContaining('full reading journal'), findsNothing);
    });

    testWidgets('tapping the locked insights reaches the paywall', (
      tester,
    ) async {
      await pumpJournal(
        tester,
        [],
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
      );

      final row = find.text(
        'cactus pro unlocks your reading trends, genres and tags — '
        'tap to upgrade',
      );
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(find.byType(PaywallPage), findsOneWidget);
      expect(
        tester.widget<PaywallPage>(find.byType(PaywallPage)).feature,
        PaywallFeature.readingUnlocked,
      );
      expect(find.text('Your Reading, Unlocked'), findsOneWidget);
    });

    testWidgets('a free reader sees reading days, but tags only as a preview', (
      tester,
    ) async {
      await pumpJournal(
        tester,
        [],
        tags: [
          BookTag(
            id: 't1',
            userBookId: 'u1',
            tag: 'my secret tag',
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        ],
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
      );

      expect(find.text('reading days'), findsOneWidget);
      expect(
        find.text('nothing logged in ${DateTime.now().year} yet.'),
        findsOneWidget,
      );
      // The locked preview's tags are invented, never the reader's own.
      expect(find.text('my secret tag'), findsNothing);
      expect(find.text('book club'), findsOneWidget);
    });
  });
}
