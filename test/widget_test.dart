import 'package:book/core/auth/session_service.dart';
import 'package:book/core/purchases/plan_controller.dart';
import 'package:book/features/library/data/book_cache_repository.dart';
import 'package:book/features/library/data/book_notes_repository.dart';
import 'package:book/features/library/data/google_book.dart';
import 'package:book/features/library/data/google_books_api_client.dart';
import 'package:book/features/library/data/reading_event_repository.dart';
import 'package:book/features/library/data/user_book_repository.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/book_lookup_service.dart';
import 'package:book/features/library/domain/book_note.dart';
import 'package:book/features/library/domain/collections.dart';
import 'package:book/features/library/domain/library_book.dart';
import 'package:book/features/library/domain/library_exception.dart';
import 'package:book/features/library/domain/reading_event.dart';
import 'package:book/features/library/domain/user_book.dart';
import 'package:book/features/library/presentation/controllers/library_controller.dart';
import 'package:book/features/logging/presentation/pages/home_page.dart';
import 'package:book/features/memory/data/memory_repository.dart';
import 'package:book/features/memory/domain/memory.dart';
import 'package:book/features/memory/presentation/controllers/memory_controller.dart';
import 'package:book/features/settings/presentation/pages/settings_page.dart';
import 'package:book/features/streaks/presentation/pages/stats_page.dart';
import 'package:book/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_collections.dart';
import 'support/fake_goals.dart';

/// The log page's own flow (parsing, animation, timers) is what these
/// tests exercise — not the real Supabase/Google Books integration
/// (covered separately under test/library). A fixed [Book] with no
/// known page count keeps `update`/`finish` unconditionally acceptable,
/// so these tests don't have to track a running page total.
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
/// precede `update`/`finish`, same as the real (Supabase-backed) one.
class _InMemoryUserBookRepository extends UserBookRepository {
  final Set<String> _started = {};

  // RootShell builds every page eagerly (IndexedStack), so LibraryPage's
  // own load() fires in the background during these tests too — give it
  // a real answer instead of letting it hit the uninitialized Supabase
  // client. Empty is fine: none of these tests look at the library page.
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

  @override
  Future<StartOutcome> addWithStatus(
    String bookId,
    ReadingStatus status, {
    int currentPage = 0,
    String? shelfId,
    DateTime? startedAt,
    DateTime? finishedAt,
  }) async {
    final isNew = _started.add(bookId);
    return StartOutcome(
      UserBook(
        id: 'progress-$bookId',
        bookId: bookId,
        currentPage: 0,
        status: status,
        shelfId: shelfId,
      ),
      alreadyExists: !isNew,
    );
  }

  ReadingStatus _status = ReadingStatus.reading;

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
    );
  }

  @override
  Future<UserBook> rate({
    required String userBookId,
    required double rating,
  }) async {
    return UserBook(
      id: userBookId,
      bookId: 'book-1',
      currentPage: 0,
      status: _status,
      rating: rating,
    );
  }

  final deleted = <String>[];

  @override
  Future<void> delete(String userBookId) async => deleted.add(userBookId);
}

/// A session that answers without a Supabase client behind it. There is
/// no gate in front of the app any more — `main` opens the session
/// before the first frame — so this exists purely so the settings screen
/// can be reached from the gear without reaching for `Supabase.instance`.
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

/// A reading-event log that never touches Supabase. [failure], when
/// set, is what [fetchForYear] throws — the streaks page renders quite
/// differently when its year could not be loaded at all, and that
/// difference is worth testing.
class _FakeReadingEventRepository extends ReadingEventRepository {
  _FakeReadingEventRepository({this.failure});

  final LibraryException? failure;

  @override
  Future<void> log(
    ReadingEventType type, {
    required String title,
    DateTime? occurredAt,
    double? value,
  }) async {}

  @override
  Future<List<ReadingEvent>> fetchForYear(int year) async {
    if (failure != null) throw failure!;
    return const [];
  }
}

/// In-memory tags and comments, so `add tag`/`add comment` never reach the
/// uninitialized Supabase client.
class _InMemoryNotesRepository extends BookNotesRepository {
  // The stats page's pro "tags" section reads every tag at once.
  @override
  Future<List<BookTag>> fetchAllTags() async => const [];

  @override
  Future<BookTag> addTag(String userBookId, ReaderTag tag) async => BookTag(
    id: 'book-tag',
    userBookId: userBookId,
    tag: tag.name,
    createdAt: DateTime(2026),
  );

  @override
  Future<BookComment> addComment(String userBookId, String body) async =>
      BookComment(
        id: 'comment',
        userBookId: userBookId,
        body: BookNotesRepository.validateComment(body),
        createdAt: DateTime(2026),
      );
}

LibraryController _newLibraryController({LibraryException? eventsFailure}) {
  return LibraryController(
    lookup: BookLookupService(
      cache: _AlwaysHitCache(),
      googleBooks: GoogleBooksApiClient(
        client: MockClient((_) async => http.Response('unused', 200)),
      ),
    ),
    userBooks: _InMemoryUserBookRepository(),
    events: _FakeReadingEventRepository(failure: eventsFailure),
    notes: _InMemoryNotesRepository(),
    collections: FakeCollectionsRepository(),
  );
}

/// In-memory memories, fresh per test — `HomePage` and `MemoryPage`
/// both kick a `load()` off in `initState`, which would otherwise hit
/// the uninitialized Supabase client the same way `LibraryPage`'s own
/// load does (see `_InMemoryUserBookRepository`'s comment above).
class _InMemoryMemoryRepository extends MemoryRepository {
  int _nextId = 0;

  @override
  Future<List<Memory>> fetchAll() async => const [];

  @override
  Future<Memory> add({String? bookTitle, required String note}) async {
    return Memory(
      id: 'memory-${_nextId++}',
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
  // flutter_test's default surface (800x600) is smaller than any real
  // phone; size it like one so overflow checks reflect a real device.
  Future<void> useDeviceSize(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> goToStatsPage(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.local_fire_department_outlined));
    await tester.pumpAndSettle();
  }

  /// Submits [text] and returns once the outcome has been decided, but
  /// before any accept animation has run.
  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    // One pump lets the (fake, immediate) library call resolve; a
    // second renders the frame it triggers — the confirmation waits on
    // that result instead of firing optimistically.
    await tester.pump();
    await tester.pump();
  }

  /// Runs an in-flight accept sequence out to the frame that clears the
  /// field. Must be reached before a test ends, or the hold timer is
  /// still pending at teardown.
  Future<void> finishAccept(WidgetTester tester) async {
    // The strike/checkmark animation, then the hold before the clear —
    // pumped separately because the hold's timer is only created once
    // the animation's future has resolved.
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
  }

  /// Submits [text] and runs the full accept sequence to completion, so
  /// the field is empty and editable again on return.
  Future<void> submit(WidgetTester tester, String text) async {
    await send(tester, text);
    await finishAccept(tester);
  }

  testWidgets(
    'Log page is the default view, with a text box that confirms on submit',
    (WidgetTester tester) async {
      await useDeviceSize(tester);
      await tester.pumpWidget(
        BookApp(
          libraryController: _newLibraryController(),
          memoryController: _newMemoryController(),
          sessionService: _FakeSession(),
          goalController: goalControllerFor(),
        ),
      );

      expect(find.byType(TextField), findsOneWidget);

      await submit(tester, 'start Dune');
      expect(find.text('Started "Dune"'), findsOneWidget);
    },
  );

  testWidgets('recognizes update, finish, and rate commands', (
    WidgetTester tester,
  ) async {
    await useDeviceSize(tester);
    await tester.pumpWidget(
      BookApp(
        libraryController: _newLibraryController(),
        memoryController: _newMemoryController(),
        sessionService: _FakeSession(),
        goalController: goalControllerFor(),
      ),
    );

    await submit(tester, 'start Dune');
    expect(find.text('Started "Dune"'), findsOneWidget);

    await submit(tester, 'update Dune 120');
    expect(find.text('"Dune" — pg 120'), findsOneWidget);

    await submit(tester, 'finish Dune');
    expect(find.text('Finished "Dune"'), findsOneWidget);

    await submit(tester, 'rate Dune 5');
    expect(find.text('"Dune" — 5★'), findsOneWidget);
  });

  for (final (command, confirmation) in [
    ('move Dune tbr', 'Added "Dune" to read'),
    ('move Dune finished', 'Added "Dune" as finished'),
    ('move Dune "dnf"', 'Marked "Dune" as DNF'),
  ]) {
    testWidgets('recognizes $command', (WidgetTester tester) async {
      await useDeviceSize(tester);
      await tester.pumpWidget(
        BookApp(
          libraryController: _newLibraryController(),
          memoryController: _newMemoryController(),
          sessionService: _FakeSession(),
          goalController: goalControllerFor(),
        ),
      );

      await submit(tester, command);
      expect(find.text(confirmation), findsOneWidget);
    });
  }

  testWidgets('tags and comments a book already on the shelf', (
    WidgetTester tester,
  ) async {
    await useDeviceSize(tester);
    await tester.pumpWidget(
      BookApp(
        libraryController: _newLibraryController(),
        memoryController: _newMemoryController(),
        sessionService: _FakeSession(),
        goalController: goalControllerFor(),
      ),
    );

    await submit(tester, 'start Dune');
    await submit(tester, 'make tag sci-fi');
    expect(find.text('Made tag "sci-fi"'), findsOneWidget);
    await submit(tester, 'add tag sci-fi Dune');
    expect(find.text('Tagged "Dune" sci-fi'), findsOneWidget);

    await submit(tester, 'add comment "slow first half" Dune');
    expect(find.text('Commented on "Dune"'), findsOneWidget);

    // Unquoted: only the library knows where the comment stops — so the
    // pill names the book the library found, not the parser's guess.
    await submit(tester, 'add comment slow first half dune');
    expect(find.text('Commented on "Dune"'), findsOneWidget);
  });

  testWidgets('tagging a book that is not on the shelf adds it to read first', (
    WidgetTester tester,
  ) async {
    await useDeviceSize(tester);
    await tester.pumpWidget(
      BookApp(
        libraryController: _newLibraryController(),
        memoryController: _newMemoryController(),
        sessionService: _FakeSession(),
        goalController: goalControllerFor(),
      ),
    );

    // Free plan: two tags are allowed.
    await submit(tester, 'make tag sci-fi');
    await submit(tester, 'add tag sci-fi Dune');
    // The library's own message, since the parser can't know it was added.
    expect(
      find.text('Added "Dune" to read and tagged it sci-fi'),
      findsOneWidget,
    );
  });

  testWidgets('a tag that was never made is refused, not created', (
    WidgetTester tester,
  ) async {
    await useDeviceSize(tester);
    await tester.pumpWidget(
      BookApp(
        libraryController: _newLibraryController(),
        memoryController: _newMemoryController(),
        sessionService: _FakeSession(),
        goalController: goalControllerFor(),
      ),
    );

    await submit(tester, 'start Dune');
    await send(tester, 'add tag sci-fi Dune');
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text(
        'No tag called "sci-fi" yet — make it first with make tag sci-fi.',
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
    'make shelf is refused on the free plan, with an upgrade message',
    (WidgetTester tester) async {
      await useDeviceSize(tester);
      await tester.pumpWidget(
        BookApp(
          libraryController: _newLibraryController(),
          memoryController: _newMemoryController(),
          sessionService: _FakeSession(),
          goalController: goalControllerFor(),
        ),
      );

      await submit(tester, 'make shelf summer reads');
      expect(
        find.text('Upgrade to cactus pro to make custom shelves.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('strikes the command through in place, then clears the field', (
    WidgetTester tester,
  ) async {
    await useDeviceSize(tester);
    await tester.pumpWidget(
      BookApp(
        libraryController: _newLibraryController(),
        memoryController: _newMemoryController(),
        sessionService: _FakeSession(),
        goalController: goalControllerFor(),
      ),
    );

    await send(tester, 'start Dune');

    // The same field is still there, still holding the same text — the
    // strike is drawn on it rather than replacing it.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('start Dune'), findsOneWidget);

    await finishAccept(tester);

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('start Dune'), findsNothing);
  });

  testWidgets(
    'the struck-through text keeps the exact size and position it had '
    'while being typed',
    (WidgetTester tester) async {
      await useDeviceSize(tester);
      await tester.pumpWidget(
        BookApp(
          libraryController: _newLibraryController(),
          memoryController: _newMemoryController(),
          sessionService: _FakeSession(),
          goalController: goalControllerFor(),
        ),
      );

      final editable = find.byType(EditableText);
      TextStyle styleNow() => tester.widget<EditableText>(editable).style;

      await tester.enterText(find.byType(TextField), 'start Dune');
      await tester.pump();
      final typedRect = tester.getRect(editable);
      final typedStyle = styleNow();

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();

      // Sampled across the strike — start, middle, and end — because a
      // swap-in stand-in widget would only betray itself on the frames
      // where it is actually mounted.
      for (final elapsed in const [0, 150, 300, 550]) {
        await tester.pump(Duration(milliseconds: elapsed));
        expect(
          tester.getRect(editable),
          typedRect,
          reason: 'text moved or resized ${elapsed}ms into the strike',
        );
        expect(styleNow().fontSize, typedStyle.fontSize);
        expect(styleNow().height, typedStyle.height);
        expect(styleNow().color, typedStyle.color);
      }

      await finishAccept(tester);
    },
  );

  testWidgets('the strikethrough grows across the text as it animates', (
    WidgetTester tester,
  ) async {
    await useDeviceSize(tester);
    await tester.pumpWidget(
      BookApp(
        libraryController: _newLibraryController(),
        memoryController: _newMemoryController(),
        sessionService: _FakeSession(),
        goalController: goalControllerFor(),
      ),
    );

    // Counts characters carrying a lineThrough decoration in whatever
    // the field is currently rendering — the strike's actual extent.
    int struckCharacters() {
      final span = tester
          .widget<EditableText>(find.byType(EditableText))
          .controller
          .buildTextSpan(
            context: tester.element(find.byType(EditableText)),
            withComposing: false,
          );
      var struck = 0;
      span.visitChildren((visited) {
        if (visited is TextSpan &&
            visited.style?.decoration == TextDecoration.lineThrough) {
          struck += visited.text?.length ?? 0;
        }
        return true;
      });
      return struck;
    }

    await send(tester, 'start Dune');
    expect(struckCharacters(), 0, reason: 'nothing struck before it animates');

    await tester.pump(const Duration(milliseconds: 200));
    final midway = struckCharacters();
    expect(midway, greaterThan(0));
    expect(midway, lessThan('start Dune'.length));

    await tester.pump(const Duration(milliseconds: 600));
    expect(struckCharacters(), 'start Dune'.length);

    await finishAccept(tester);
  });

  testWidgets('keeps the field and shakes for an unrecognized command', (
    WidgetTester tester,
  ) async {
    await useDeviceSize(tester);
    await tester.pumpWidget(
      BookApp(
        libraryController: _newLibraryController(),
        memoryController: _newMemoryController(),
        sessionService: _FakeSession(),
        goalController: goalControllerFor(),
      ),
    );

    await tester.enterText(find.byType(TextField), 'gibberish');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.textContaining('Not recognized'), findsOneWidget);
  });

  testWidgets(
    'keeps the field and shakes for a recognized command that fails to '
    'apply — e.g. starting a book already on the shelf',
    (WidgetTester tester) async {
      await useDeviceSize(tester);
      await tester.pumpWidget(
        BookApp(
          libraryController: _newLibraryController(),
          memoryController: _newMemoryController(),
          sessionService: _FakeSession(),
          goalController: goalControllerFor(),
        ),
      );

      await submit(tester, 'start Dune');
      expect(find.text('Started "Dune"'), findsOneWidget);

      // Same book again — the second start is a no-op, not a success.
      await send(tester, 'start Dune');

      expect(find.text('"Dune" is already on your shelf.'), findsOneWidget);
      // The text stays put for correcting, and no strike runs over it.
      expect(find.text('start Dune'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 800));
      expect(
        find.text('start Dune'),
        findsOneWidget,
        reason: 'a rejected command must not be struck through or cleared',
      );
    },
  );

  testWidgets('refuses to rate a book that is not finished yet', (
    WidgetTester tester,
  ) async {
    await useDeviceSize(tester);
    await tester.pumpWidget(
      BookApp(
        libraryController: _newLibraryController(),
        memoryController: _newMemoryController(),
        sessionService: _FakeSession(),
        goalController: goalControllerFor(),
      ),
    );

    await submit(tester, 'start Dune');
    await send(tester, 'rate Dune 5');

    expect(find.text('Finish "Dune" before rating it.'), findsOneWidget);
    // Rejected like any other failed command: text stays, no strike.
    expect(find.text('rate Dune 5'), findsOneWidget);
  });

  testWidgets(
    'clears the confirmation pill on its own after a few seconds, for '
    'both success and error',
    (WidgetTester tester) async {
      await useDeviceSize(tester);
      await tester.pumpWidget(
        BookApp(
          libraryController: _newLibraryController(),
          memoryController: _newMemoryController(),
          sessionService: _FakeSession(),
          goalController: goalControllerFor(),
        ),
      );

      await submit(tester, 'start Dune');
      expect(find.text('Started "Dune"'), findsOneWidget);
      // Let the lifetime timer fire, then pump incrementally so the
      // fade-out animation it kicks off actually ticks to completion.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Started "Dune"'), findsNothing);

      await tester.enterText(find.byType(TextField), 'gibberish');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.textContaining('Not recognized'), findsOneWidget);
      // Let the lifetime timer fire, then pump incrementally so the
      // fade-out animation it kicks off actually ticks to completion.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.textContaining('Not recognized'), findsNothing);
    },
  );

  testWidgets('the settings gear opens the settings screen', (
    WidgetTester tester,
  ) async {
    await useDeviceSize(tester);
    await tester.pumpWidget(
      BookApp(
        libraryController: _newLibraryController(),
        memoryController: _newMemoryController(),
        sessionService: _FakeSession(),
        goalController: goalControllerFor(),
      ),
    );

    // One gear per top-level page, all four of them built eagerly into
    // the IndexedStack — so tap the one on the page actually on screen.
    // (Its 'Settings' semantics label is pinned down separately, in
    // test/accessibility/semantics_test.dart.)
    await tester.tap(
      find.descendant(
        of: find.byType(HomePage),
        matching: find.byIcon(Icons.settings_outlined),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('yearly goal'), findsOneWidget);
  });

  testWidgets('typing memory opens the Memory tab — on the free plan, its '
      'locked preview', (WidgetTester tester) async {
    await useDeviceSize(tester);
    await tester.pumpWidget(
      BookApp(
        libraryController: _newLibraryController(),
        memoryController: _newMemoryController(),
        sessionService: _FakeSession(),
        goalController: goalControllerFor(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '  Memory ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      tester.widget<IndexedStack>(find.byType(IndexedStack)).index,
      0,
      reason: 'switched to the Memory tab',
    );
    expect(
      find.text('cactus pro unlocks your full reading memory — tap to upgrade'),
      findsOneWidget,
    );
    // Not treated as an unrecognized command: no error pill was raised.
    expect(find.textContaining("didn't recognize"), findsNothing);
  });

  testWidgets('Stats page is reachable, with reading days and no journal', (
    WidgetTester tester,
  ) async {
    await useDeviceSize(tester);
    PlanController.isPro.value = true;
    addTearDown(() => PlanController.isPro.value = false);
    await tester.pumpWidget(
      BookApp(
        libraryController: _newLibraryController(),
        memoryController: _newMemoryController(),
        sessionService: _FakeSession(),
        goalController: goalControllerFor(),
      ),
    );
    await goToStatsPage(tester);

    expect(
      find.text('nothing logged in ${DateTime.now().year} yet.'),
      findsOneWidget,
    );
    expect(find.text('journal'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  // Performance: the stats tab used to be built (and start its own journal
  // fetch) at launch, before a reader ever opened it.
  testWidgets('a tab is only built once it is opened, and kept after', (
    WidgetTester tester,
  ) async {
    await useDeviceSize(tester);
    await tester.pumpWidget(
      BookApp(
        libraryController: _newLibraryController(),
        memoryController: _newMemoryController(),
        sessionService: _FakeSession(),
        goalController: goalControllerFor(),
      ),
    );
    await tester.pump();

    expect(find.byType(StatsPage, skipOffstage: false), findsNothing);
    expect(find.byType(HomePage), findsOneWidget);

    // The tab bar's icon — the add tab's streak readout shares the glyph.
    await tester.tap(find.byIcon(Icons.local_fire_department_outlined).last);
    await tester.pumpAndSettle();
    expect(find.byType(StatsPage), findsOneWidget);

    await tester.tap(find.byIcon(Icons.menu_book_outlined));
    await tester.pumpAndSettle();
    // Still mounted behind the library tab, state intact.
    expect(find.byType(StatsPage, skipOffstage: false), findsOneWidget);
  });

  testWidgets(
    'Stats page says so when the year could not be loaded, rather than '
    'showing an empty heatmap',
    (WidgetTester tester) async {
      await useDeviceSize(tester);
      PlanController.isPro.value = true;
      addTearDown(() => PlanController.isPro.value = false);
      await tester.pumpWidget(
        BookApp(
          libraryController: _newLibraryController(
            eventsFailure: const NetworkException('You are offline.'),
          ),
          memoryController: _newMemoryController(),
          sessionService: _FakeSession(),
          goalController: goalControllerFor(),
        ),
      );
      await goToStatsPage(tester);

      // An empty heatmap would be indistinguishable from "you have never
      // logged anything", so the failure must show instead.
      expect(find.text('You are offline.'), findsOneWidget);
      expect(find.text('try again'), findsOneWidget);
      expect(
        find.text('nothing logged in ${DateTime.now().year} yet.'),
        findsNothing,
      );
    },
  );

  testWidgets('delete asks first — cancelling keeps the book and does not '
      'shake', (WidgetTester tester) async {
    await useDeviceSize(tester);
    final library = _newLibraryController();
    await tester.pumpWidget(
      BookApp(
        libraryController: library,
        memoryController: _newMemoryController(),
        sessionService: _FakeSession(),
        goalController: goalControllerFor(),
      ),
    );
    await submit(tester, 'start Dune');

    await send(tester, 'delete dune');
    await tester.pumpAndSettle();
    expect(find.text('delete Dune?'), findsOneWidget);

    await tester.tap(find.text('cancel'));
    await tester.pumpAndSettle();

    expect(find.text('delete Dune?'), findsNothing);
    expect(find.text('Kept "Dune"'), findsOneWidget);
    expect(library.match('Dune'), isNotNull);
    // Still in the field, ready to edit or resubmit.
    expect(find.text('delete dune'), findsOneWidget);
  });

  testWidgets('remove tag with no book asks first, then unmakes the tag', (
    WidgetTester tester,
  ) async {
    await useDeviceSize(tester);
    final library = _newLibraryController();
    await tester.pumpWidget(
      BookApp(
        libraryController: library,
        memoryController: _newMemoryController(),
        sessionService: _FakeSession(),
        goalController: goalControllerFor(),
      ),
    );
    await submit(tester, 'make tag sci-fi');

    await send(tester, 'remove tag sci-fi');
    await tester.pumpAndSettle();
    expect(find.text('remove tag "sci-fi"?'), findsOneWidget);
    await tester.tap(find.text('cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Kept "sci-fi"'), findsOneWidget);
    expect(library.tags, hasLength(1));

    // Still in the field: submit it again and confirm this time.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.text('remove'));
    await tester.pumpAndSettle();

    expect(library.tags, isEmpty);
    expect(find.text('Removed tag "sci-fi"'), findsOneWidget);
    // Let the pill's own lifetime run out.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('confirming a delete removes the book', (
    WidgetTester tester,
  ) async {
    await useDeviceSize(tester);
    final library = _newLibraryController();
    await tester.pumpWidget(
      BookApp(
        libraryController: library,
        memoryController: _newMemoryController(),
        sessionService: _FakeSession(),
        goalController: goalControllerFor(),
      ),
    );
    await submit(tester, 'start Dune');

    await send(tester, 'delete Dune');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(InkWell, 'delete'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Removed "Dune"'), findsOneWidget);
    expect(library.match('Dune'), isNull);
    await finishAccept(tester);
    await tester.pumpAndSettle();
  });

  testWidgets('deleting a book that is not on the shelf skips the question', (
    WidgetTester tester,
  ) async {
    await useDeviceSize(tester);
    await tester.pumpWidget(
      BookApp(
        libraryController: _newLibraryController(),
        memoryController: _newMemoryController(),
        sessionService: _FakeSession(),
        goalController: goalControllerFor(),
      ),
    );

    await send(tester, 'delete Dune');
    await tester.pump();
    expect(find.text('delete Dune?'), findsNothing);
    expect(
      find.text("You haven't started \"Dune\" yet — try \"start Dune\" first."),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 4));
  });
}
