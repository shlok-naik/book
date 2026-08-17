import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:book/features/library/data/book_cache_repository.dart';
import 'package:book/features/library/data/google_book.dart';
import 'package:book/features/library/data/google_books_api_client.dart';
import 'package:book/features/library/data/user_book_repository.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/book_lookup_service.dart';
import 'package:book/features/library/domain/library_book.dart';
import 'package:book/features/library/domain/user_book.dart';
import 'package:book/features/library/presentation/controllers/library_controller.dart';
import 'package:book/main.dart';
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

  @override
  Future<UserBook> saveProgress({
    required String userBookId,
    required int currentPage,
    required bool finished,
  }) async {
    return UserBook(
      id: userBookId,
      bookId: 'book-1',
      currentPage: currentPage,
      status: finished ? ReadingStatus.finished : ReadingStatus.reading,
    );
  }
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
  );
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

  Future<void> submit(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    // One pump lets the (fake, immediate) library call resolve; a
    // second renders the frame it triggers — needed now that the
    // confirmation waits on that result instead of firing optimistically.
    await tester.pump();
    await tester.pump();
    // Let the strike-through/checkmark animation finish and the field
    // reset, so the next submit() can find the TextField again.
    await tester.pump(const Duration(milliseconds: 1400));
  }

  testWidgets('Log page is the default view, with a text box that confirms on submit',
      (WidgetTester tester) async {
    await useDeviceSize(tester);
    await tester.pumpWidget(BookApp(libraryController: _newLibraryController()));

    expect(find.byType(TextField), findsOneWidget);

    await submit(tester, 'start Dune');
    expect(find.text('Started "Dune"'), findsOneWidget);
  });

  testWidgets('recognizes update, finish, and rate commands',
      (WidgetTester tester) async {
    await useDeviceSize(tester);
    await tester.pumpWidget(BookApp(libraryController: _newLibraryController()));

    await submit(tester, 'start Dune');
    expect(find.text('Started "Dune"'), findsOneWidget);

    await submit(tester, 'update Dune 120');
    expect(find.text('"Dune" — pg 120'), findsOneWidget);

    await submit(tester, 'finish Dune');
    expect(find.text('Finished "Dune"'), findsOneWidget);

    await submit(tester, 'rate Dune 5');
    expect(find.text('"Dune" — 5★'), findsOneWidget);
  });

  testWidgets(
      'shows a strikethrough + checkmark in place of the field right after '
      'a valid command, then resets it', (WidgetTester tester) async {
    await useDeviceSize(tester);
    await tester.pumpWidget(BookApp(libraryController: _newLibraryController()));

    await tester.enterText(find.byType(TextField), 'start Dune');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    // Let the (fake, immediate) library call resolve and its frame render.
    await tester.pump();
    await tester.pump();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('start Dune'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1400));
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('keeps the field and shakes for an unrecognized command',
      (WidgetTester tester) async {
    await useDeviceSize(tester);
    await tester.pumpWidget(BookApp(libraryController: _newLibraryController()));

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
    await tester.pumpWidget(BookApp(libraryController: _newLibraryController()));

    await submit(tester, 'start Dune');
    expect(find.text('Started "Dune"'), findsOneWidget);

    // Same book again — the second start is a no-op, not a success.
    await tester.enterText(find.byType(TextField), 'start Dune');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();

    expect(
      find.byType(TextField),
      findsOneWidget,
      reason: 'a failed command must not swap in the checkmark',
    );
    expect(find.text('start Dune'), findsOneWidget);
    expect(find.text('"Dune" is already on your shelf.'), findsOneWidget);
  });

  testWidgets(
      'clears the confirmation pill on its own after a few seconds, for '
      'both success and error', (WidgetTester tester) async {
    await useDeviceSize(tester);
    await tester.pumpWidget(BookApp(libraryController: _newLibraryController()));

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
  });

  testWidgets('Streaks page is reachable and grouped by month',
      (WidgetTester tester) async {
    await useDeviceSize(tester);
    await tester.pumpWidget(BookApp(libraryController: _newLibraryController()));
    await goToStreaksPage(tester);

    expect(find.text('january'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
