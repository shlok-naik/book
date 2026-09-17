import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/goals/domain/daily_goal.dart';
import 'package:book/features/goals/presentation/daily_goal_controller.dart';
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
import 'package:book/features/logging/presentation/pages/home_page.dart';
import 'package:book/features/memory/data/memory_repository.dart';
import 'package:book/features/memory/domain/memory.dart';
import 'package:book/features/memory/presentation/controllers/memory_controller.dart';
import 'package:book/features/memory/presentation/memory_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_goals.dart';

/// The add tab's "currently reading" peek and its streak readout — see
/// `ReadingStreak` and the bottom of `HomePage.build`. Both are
/// read-only summaries layered on top of already-tested library/streak
/// behaviour, so these tests are only about what shows, not about
/// re-proving the underlying data layer.

const _dune = Book(
  id: 'book-1',
  googleBooksId: 'gb-dune',
  title: 'Dune',
  author: 'Frank Herbert',
);

class _AlwaysHitCache extends BookCacheRepository {
  @override
  Future<Book?> findByTitle(String title, {String? author}) async => _dune;

  @override
  Future<Book?> findByGoogleBooksId(String id) async => _dune;
}

class _InMemoryUserBooks extends UserBookRepository {
  final _started = <String, UserBook>{};

  @override
  Future<List<LibraryBook>> fetchLibrary() async => const [];

  @override
  Future<StartOutcome> start(String bookId, {DateTime? startedAt}) async {
    final isNew = !_started.containsKey(bookId);
    final book = UserBook(
      id: 'progress-$bookId',
      bookId: bookId,
      currentPage: 0,
      status: ReadingStatus.reading,
    );
    if (isNew) _started[bookId] = book;
    return StartOutcome(book, alreadyExists: !isNew);
  }
}

class _FakeReadingEventRepository extends ReadingEventRepository {
  _FakeReadingEventRepository([this.rows = const []]);

  final List<ReadingEvent> rows;

  @override
  Future<void> log(
    ReadingEventType type, {
    required String title,
    DateTime? occurredAt,
    double? value,
  }) async {}

  @override
  Future<List<ReadingEvent>> fetchForYear(int year) async => List.of(rows);
}

class _EmptyMemoryRepository extends MemoryRepository {
  @override
  Future<List<Memory>> fetchAll() async => const [];
}

LibraryController _libraryController({List<ReadingEvent> events = const []}) {
  return LibraryController(
    lookup: BookLookupService(
      cache: _AlwaysHitCache(),
      googleBooks: GoogleBooksApiClient(
        client: MockClient((_) async => http.Response('unused', 200)),
      ),
    ),
    userBooks: _InMemoryUserBooks(),
    events: _FakeReadingEventRepository(events),
  );
}

/// Raises or lowers a pretend on-screen keyboard. The add tab's
/// currently-reading card, goal and streak hide while it's up — the keyboard
/// takes their place (see `HomePage._keyboardVisible`) — and a test view has
/// no keyboard of its own, so these tests put one there.
Future<void> setKeyboard(WidgetTester tester, {required bool up}) async {
  if (up) {
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
  } else {
    tester.view.resetViewInsets();
  }
  await tester.pump();
}

/// Pumps the add tab with the keyboard down (a test view has none), so the
/// card, goal and streak are showing; [keyboardUp] raises one first.
Future<void> pumpHome(
  WidgetTester tester, {
  List<ReadingEvent> events = const [],
  bool keyboardUp = false,
}) async {
  addTearDown(tester.view.resetViewInsets);
  if (keyboardUp) tester.view.viewInsets = const FakeViewPadding(bottom: 300);
  final library = _libraryController(events: events);
  final memory = MemoryController(repository: _EmptyMemoryRepository());
  addTearDown(library.dispose);
  addTearDown(memory.dispose);

  await tester.pumpWidget(
    GoalScope(
      controller: goalControllerFor(),
      child: LibraryScope(
        controller: library,
        child: MemoryScope(
          controller: memory,
          child: MaterialApp(theme: AppTheme.light, home: const HomePage()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Submits [text] and returns once the outcome has been decided, but
/// before any accept animation has run.
Future<void> send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  // One pump lets the (fake, immediate) library call resolve; a second
  // renders the frame it triggers.
  await tester.pump();
  await tester.pump();
}

/// Runs an in-flight accept sequence out to the frame that clears the
/// field.
Future<void> finishAccept(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 800));
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump();
}

/// Submits [text] and runs the full accept sequence to completion.
Future<void> submit(WidgetTester tester, String text) async {
  await send(tester, text);
  await finishAccept(tester);
}

void main() {
  group('the currently-reading peek', () {
    testWidgets('offers to start a book when nothing is in progress', (
      tester,
    ) async {
      await pumpHome(tester);
      expect(find.text('nothing logged yet — start a book.'), findsOneWidget);
    });

    testWidgets('shows the active book once one has been started', (
      tester,
    ) async {
      await pumpHome(tester);
      expect(find.textContaining('currently reading'), findsNothing);

      await submit(tester, 'start Dune');

      expect(find.text('currently reading'), findsOneWidget);
      // Twice: once as the cover's own placeholder text (no coverUrl in
      // this fake), once as the card's title.
      expect(find.text('Dune'), findsWidgets);
      expect(find.text('not started'), findsOneWidget);
    });

    testWidgets('disappears when the keyboard comes up, and returns when '
        'it goes back down', (tester) async {
      await pumpHome(tester);
      await submit(tester, 'start Dune');
      expect(find.textContaining('currently reading'), findsOneWidget);

      await setKeyboard(tester, up: true);
      expect(find.textContaining('currently reading'), findsNothing);

      await setKeyboard(tester, up: false);
      expect(find.textContaining('currently reading'), findsOneWidget);
    });

    testWidgets('stays while typing with no keyboard — only the keyboard '
        'decides', (tester) async {
      await pumpHome(tester);
      await tester.enterText(find.byType(TextField), 'u');
      await tester.pump();
      expect(find.text('nothing logged yet — start a book.'), findsOneWidget);
    });

    testWidgets('a page opened with the keyboard up shows none of it', (
      tester,
    ) async {
      await pumpHome(tester, keyboardUp: true);
      expect(find.text('nothing logged yet — start a book.'), findsNothing);
      expect(find.text('no streak yet'), findsNothing);
    });
  });

  group('the streak readout', () {
    testWidgets('says so when nothing has been logged yet', (tester) async {
      await pumpHome(tester);
      expect(find.text('no streak yet'), findsOneWidget);
    });

    testWidgets('hides with the keyboard, same as the reading row', (
      tester,
    ) async {
      await pumpHome(tester);
      expect(find.text('no streak yet'), findsOneWidget);

      await setKeyboard(tester, up: true);
      expect(find.text('no streak yet'), findsNothing);

      await setKeyboard(tester, up: false);
      expect(find.text('no streak yet'), findsOneWidget);
    });

    testWidgets('a ticked daily goal counts as a day read', (tester) async {
      SharedPreferences.setMockInitialValues({});
      addTearDown(DailyGoalController.reset);
      await pumpHome(tester);
      expect(find.text('no streak yet'), findsOneWidget);

      // The one "I read today" the app has: no command, no book — the
      // question above the row, ticked.
      await tester.tap(find.byKey(const ValueKey('daily-goal-done')));
      await tester.pump();

      expect(find.text('1 day streak'), findsOneWidget);
    });

    testWidgets('yesterday ticked keeps the run going', (tester) async {
      final now = DateTime.now();
      SharedPreferences.setMockInitialValues({});
      addTearDown(DailyGoalController.reset);
      DailyGoalController.reset(
        DailyGoal(
          minutes: 10,
          doneDays: {
            DailyGoal.keyOf(now.subtract(const Duration(days: 1))),
            DailyGoal.keyOf(now.subtract(const Duration(days: 2))),
          },
        ),
      );
      await pumpHome(tester);

      expect(find.text('2 day streak'), findsOneWidget);
    });

    testWidgets('counts consecutive days ending today', (tester) async {
      final now = DateTime.now();
      await pumpHome(
        tester,
        events: [
          ReadingEvent(
            type: ReadingEventType.start,
            occurredAt: now.toUtc(),
            title: 'Dune',
          ),
          ReadingEvent(
            type: ReadingEventType.update,
            occurredAt: now.subtract(const Duration(days: 1)).toUtc(),
            title: 'Dune',
            value: 50,
          ),
        ],
      );

      expect(find.text('2 day streak'), findsOneWidget);
    });
  });
}
