import 'package:book/features/library/data/book_cache_repository.dart';
import 'package:book/features/library/data/google_book.dart';
import 'package:book/features/library/data/google_books_api_client.dart';
import 'package:book/features/library/data/reading_event_repository.dart';
import 'package:book/features/library/data/user_book_repository.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/book_lookup_service.dart';
import 'package:book/features/library/domain/library_book.dart';
import 'package:book/features/library/domain/library_exception.dart';
import 'package:book/features/library/domain/reading_event.dart';
import 'package:book/features/library/domain/user_book.dart';
import 'package:book/features/library/presentation/controllers/library_controller.dart';
import 'package:book/features/memory/data/memory_repository.dart';
import 'package:book/features/memory/domain/memory.dart';
import 'package:book/features/memory/presentation/controllers/memory_controller.dart';
import 'package:book/features/onboarding/data/session_service.dart';
import 'package:book/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
  Future<StartOutcome> start(String bookId) async {
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
}

/// These tests exercise the log page's own flow, which starts past the
/// onboarding gate — so every `BookApp` in this file is built already
/// signed in, without a real Supabase session.
class _AlwaysSignedIn extends SessionService {
  @override
  bool get isSignedIn => true;
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
  }) async {}

  @override
  Future<List<ReadingEvent>> fetchForYear(int year) async {
    if (failure != null) throw failure!;
    return const [];
  }
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
  );
}

/// In-memory memories, fresh per test — `HomePage` and `ProfilePage`
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

  Future<void> goToStreaksPage(WidgetTester tester) async {
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
          sessionService: _AlwaysSignedIn(),
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
        sessionService: _AlwaysSignedIn(),
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

  testWidgets('strikes the command through in place, then clears the field', (
    WidgetTester tester,
  ) async {
    await useDeviceSize(tester);
    await tester.pumpWidget(
      BookApp(
        libraryController: _newLibraryController(),
        memoryController: _newMemoryController(),
        sessionService: _AlwaysSignedIn(),
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
          sessionService: _AlwaysSignedIn(),
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
        sessionService: _AlwaysSignedIn(),
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
        sessionService: _AlwaysSignedIn(),
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
          sessionService: _AlwaysSignedIn(),
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
        sessionService: _AlwaysSignedIn(),
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
          sessionService: _AlwaysSignedIn(),
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

  testWidgets('Streaks page is reachable and grouped by month', (
    WidgetTester tester,
  ) async {
    await useDeviceSize(tester);
    await tester.pumpWidget(
      BookApp(
        libraryController: _newLibraryController(),
        memoryController: _newMemoryController(),
        sessionService: _AlwaysSignedIn(),
      ),
    );
    await goToStreaksPage(tester);

    expect(find.text('january'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets(
    'Streaks page says so when the year could not be loaded, rather than '
    'drawing an empty one',
    (WidgetTester tester) async {
      await useDeviceSize(tester);
      await tester.pumpWidget(
        BookApp(
          libraryController: _newLibraryController(
            eventsFailure: const NetworkException('You are offline.'),
          ),
          memoryController: _newMemoryController(),
          sessionService: _AlwaysSignedIn(),
        ),
      );
      await goToStreaksPage(tester);

      // An empty grid would be indistinguishable from "you have never
      // logged anything", so the months must not be drawn at all.
      expect(find.text('january'), findsNothing);
      expect(find.text('You are offline.'), findsOneWidget);
      expect(find.text('try again'), findsOneWidget);
    },
  );
}
