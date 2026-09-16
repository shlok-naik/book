// Integration tests — unlike everything under test/, these run the real
// compiled app on a real device or emulator (`flutter test
// integration_test/app_test.dart -d <device>`), driving real navigation,
// real animations, and real platform channels rather than a headless Dart
// VM. What's faked is only the bottom layer — Supabase/Google Books — the
// same fakes test/widget_test.dart already uses, injected through
// `BookApp`'s own test seams (see CLAUDE.md § Composition root), so these
// stay deterministic and offline while still exercising the real widget
// tree `main()` builds on a device.
//
// See CLAUDE.md § Testing Strategy → Integration Tests for which journeys
// this is meant to cover.

import 'package:book/core/auth/session_service.dart';
import 'package:book/features/library/data/book_cache_repository.dart';
import 'package:book/features/library/data/google_book.dart';
import 'package:book/features/library/data/google_books_api_client.dart';
import 'package:book/features/library/data/reading_event_repository.dart';
import 'package:book/features/library/data/user_book_repository.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/book_lookup_service.dart';
import 'package:book/features/library/domain/library_book.dart';
import 'package:book/features/library/domain/reading_event.dart';
import 'package:book/features/library/domain/user_book.dart';
import 'package:book/features/library/presentation/controllers/library_controller.dart';
import 'package:book/features/memory/data/memory_repository.dart';
import 'package:book/features/memory/domain/memory.dart';
import 'package:book/features/memory/presentation/controllers/memory_controller.dart';
import 'package:book/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';

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

  @override
  Future<Book> cache(GoogleBook volume) async => _dune;
}

/// In-memory shelf, fresh per test — realistic enough that `start` must
/// precede `update`/`finish`, same as the real (Supabase-backed) one, and
/// with no known page count so `update`/`finish` are unconditionally
/// acceptable — same convention test/widget_test.dart uses.
class _InMemoryUserBookRepository extends UserBookRepository {
  final Set<String> _started = {};

  @override
  Future<List<LibraryBook>> fetchLibrary() async => const [];

  @override
  Future<StartOutcome> start(String bookId, {DateTime? startedAt}) async {
    final isNew = _started.add(bookId);
    return StartOutcome(
      UserBook(
        id: 'progress-$bookId',
        bookId: bookId,
        currentPage: 0,
        status: ReadingStatus.reading,
      ),
      alreadyExists: !isNew,
    );
  }

  ReadingStatus _status = ReadingStatus.reading;
  double? _rating;

  @override
  Future<UserBook> saveProgress({
    required String userBookId,
    required int currentPage,
    required bool finished,
    DateTime? finishedAt,
  }) async {
    _status = finished ? ReadingStatus.finished : ReadingStatus.reading;
    return UserBook(
      id: userBookId,
      bookId: 'book-1',
      currentPage: currentPage,
      status: _status,
      rating: _rating,
    );
  }

  @override
  Future<UserBook> rate({
    required String userBookId,
    required double rating,
  }) async {
    _rating = rating;
    return UserBook(
      id: userBookId,
      bookId: 'book-1',
      currentPage: 0,
      status: _status,
      rating: rating,
    );
  }
}

class _FakeSession extends SessionService {
  @override
  Future<void> ensureSession() async {}

  @override
  bool get isSignedIn => true;

  @override
  bool get isAnonymous => true;

  @override
  String? get email => null;

  @override
  String? get userId => 'fake-user-id';
}

class _FakeReadingEventRepository extends ReadingEventRepository {
  @override
  Future<void> log(
    ReadingEventType type, {
    required String title,
    DateTime? occurredAt,
    double? value,
  }) async {}

  @override
  Future<List<ReadingEvent>> fetchForYear(int year) async => const [];
}

LibraryController _newLibraryController() {
  return LibraryController(
    lookup: BookLookupService(
      cache: _AlwaysHitCache(),
      googleBooks: GoogleBooksApiClient(
        client: MockClient((_) async => http.Response('unused', 200)),
      ),
    ),
    userBooks: _InMemoryUserBookRepository(),
    events: _FakeReadingEventRepository(),
  );
}

class _InMemoryMemoryRepository extends MemoryRepository {
  @override
  Future<List<Memory>> fetchAll() async => const [];

  @override
  Future<Memory> add({String? bookTitle, required String note}) async {
    return Memory(
      id: 'memory-1',
      bookTitle: bookTitle,
      note: note,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> delete(String id) async {}
}

MemoryController _newMemoryController() {
  return MemoryController(repository: _InMemoryMemoryRepository());
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Submits [text] on the log page and runs the accept animation out to
  /// completion, so the field is empty and editable again on return —
  /// same choreography test/widget_test.dart's own `submit` follows.
  Future<void> submit(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    // The strike-through/checkmark accept animation, then the hold
    // before the field clears.
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
  }

  Future<void> goToTab(WidgetTester tester, IconData icon) async {
    await tester.tap(find.byIcon(icon));
    await tester.pumpAndSettle();
  }

  group('reading journeys', () {
    testWidgets('starting a book puts it on the shelf, in progress', (
      tester,
    ) async {
      await tester.pumpWidget(
        BookApp(
          libraryController: _newLibraryController(),
          memoryController: _newMemoryController(),
          sessionService: _FakeSession(),
        ),
      );
      await tester.pumpAndSettle();

      // The log page ("add") is the default tab.
      expect(find.byType(TextField), findsOneWidget);

      await submit(tester, 'start Dune');
      expect(find.text('Started "Dune"'), findsOneWidget);

      await goToTab(tester, Icons.menu_book_outlined);

      // Shelves are folders: reading holds one book, finished none.
      expect(find.bySemanticsLabel('Reading, 1 book'), findsOneWidget);
      expect(find.bySemanticsLabel('Finished, 0 books'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Reading, 1 book'));
      await tester.pumpAndSettle();
      expect(find.text('Dune'), findsWidgets);
    });

    testWidgets(
      'finishing and rating a book moves it to the finished section',
      (tester) async {
        await tester.pumpWidget(
          BookApp(
            libraryController: _newLibraryController(),
            memoryController: _newMemoryController(),
            sessionService: _FakeSession(),
          ),
        );
        await tester.pumpAndSettle();

        await submit(tester, 'start Dune');
        await submit(tester, 'finish Dune');
        await submit(tester, 'rate Dune 4.5');

        await goToTab(tester, Icons.menu_book_outlined);

        expect(find.bySemanticsLabel('Reading, 0 books'), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('Finished, 1 book'));
        await tester.pumpAndSettle();
        expect(find.text('Dune'), findsWidgets);
      },
    );

    testWidgets('the shelf survives a full lap through every tab and back', (
      tester,
    ) async {
      await tester.pumpWidget(
        BookApp(
          libraryController: _newLibraryController(),
          memoryController: _newMemoryController(),
          sessionService: _FakeSession(),
        ),
      );
      await tester.pumpAndSettle();

      await submit(tester, 'start Dune');

      // Search → stats → library → settings → back → add: the same
      // LibraryController instance sits behind every one of these, so
      // "Dune" being on the shelf can't depend on which tab is open.
      await goToTab(tester, Icons.search);
      expect(find.text('search'), findsOneWidget);

      await goToTab(tester, Icons.local_fire_department_outlined);
      expect(find.text('stats'), findsOneWidget);

      await goToTab(tester, Icons.menu_book_outlined);
      expect(find.bySemanticsLabel('Reading, 1 book'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      expect(find.text('settings'), findsOneWidget);

      // Not `tester.pageBack()`: `_SettingsHeader`'s chevron carries
      // its "Back" label via `Semantics` rather than a `Tooltip` (see
      // its own doc comment on why it isn't a Material `BackButton`),
      // and `pageBack()` only looks for one of those two.
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();

      await goToTab(tester, Icons.add);
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
