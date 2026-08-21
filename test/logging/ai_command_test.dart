import 'package:book/core/ai/ai_command_parser.dart';
import 'package:book/core/purchases/plan_controller.dart';
import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/library/data/book_cache_repository.dart';
import 'package:book/features/library/data/google_book.dart';
import 'package:book/features/library/data/google_books_api_client.dart';
import 'package:book/features/library/data/user_book_repository.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/book_lookup_service.dart';
import 'package:book/features/library/domain/library_book.dart';
import 'package:book/features/library/domain/user_book.dart';
import 'package:book/features/library/presentation/controllers/library_controller.dart';
import 'package:book/features/library/presentation/library_scope.dart';
import 'package:book/features/logging/domain/log_command_parser.dart';
import 'package:book/features/logging/presentation/pages/home_page.dart';
import 'package:book/features/logging/presentation/widgets/command_input.dart';
import 'package:book/features/logging/presentation/widgets/confirmation_pill.dart';
import 'package:book/features/logging/presentation/widgets/instruction_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

class _InMemoryUserBookRepository extends UserBookRepository {
  final Set<String> _started = {};

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

  @override
  Future<UserBook> rate({
    required String userBookId,
    required double rating,
  }) async {
    return UserBook(
      id: userBookId,
      bookId: 'book-1',
      currentPage: 0,
      status: ReadingStatus.reading,
      rating: rating,
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

/// Stands in for a real `parse-command` call — returns [commands] (or
/// throws [failure]) without touching the network.
class FakeAiCommandParser implements AiCommandParser {
  FakeAiCommandParser({this.commands = const [], this.failure});

  final List<String> commands;
  final AiCommandException? failure;
  int extractCommandsCalls = 0;

  @override
  Future<List<String>> extractCommands(String message) async {
    extractCommandsCalls++;
    if (failure != null) throw failure!;
    return commands;
  }
}

Widget _harness(Widget child, LibraryController library) {
  return MaterialApp(
    theme: AppTheme.light,
    home: LibraryScope(controller: library, child: child),
  );
}

void main() {
  setUp(() => PlanController.isPro.value = true);
  tearDown(() => PlanController.isPro.value = false);

  Future<void> useDeviceSize(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('a sentence is swapped for its extracted commands, which run in '
      'order and clear back to an empty input', (tester) async {
    await useDeviceSize(tester);
    final ai = FakeAiCommandParser(
      commands: const ['start Dune', 'update Dune 120'],
    );
    final library = _newLibraryController();
    await tester.pumpWidget(_harness(HomePage(aiParser: ai), library));

    await tester.enterText(
      find.byType(TextField),
      "I started Dune and I'm on page 120",
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();

    expect(ai.extractCommandsCalls, 1);
    // The typed sentence is gone the moment extraction succeeds —
    // CommandInput itself is swapped out, not just cleared — and the
    // extracted commands take its place, each an InstructionRow
    // rendered with RichText (not a plain Text) in that same style.
    expect(find.byType(CommandInput), findsNothing);
    expect(find.text("I started Dune and I'm on page 120"), findsNothing);
    expect(find.text('start Dune', findRichText: true), findsOneWidget);
    expect(find.text('update Dune 120', findRichText: true), findsOneWidget);

    // First command's action resolves and its checkmark/strike plays,
    // then the second starts.
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 800));

    // Both done — the list sits for a few seconds (the confirmation
    // pill's own lifetime), then fades out and a fresh, empty
    // CommandInput comes right back in its place.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('start Dune', findRichText: true), findsNothing);
    expect(find.text('update Dune 120', findRichText: true), findsNothing);
    expect(find.byType(CommandInput), findsOneWidget);
  });

  testWidgets(
    'a failing command does not block the rest, and any success crosses '
    'out the whole sentence',
    (tester) async {
      await useDeviceSize(tester);
      final ai = FakeAiCommandParser(
        commands: const ['finish Dune', 'start Mockingbird'],
      );
      final library = _newLibraryController();
      await tester.pumpWidget(_harness(HomePage(aiParser: ai), library));

      await tester.enterText(
        find.byType(TextField),
        'finish Dune and start Mockingbird',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();

      expect(
        find.text('start Mockingbird', findRichText: true),
        findsOneWidget,
      );

      // "finish Dune" fails — the book was never started. Two more
      // zero-duration pumps flush `_runCommand`'s own await without
      // advancing the 750ms hold that follows it, so this catches the
      // pill before "start Mockingbird" gets its own turn and message.
      await tester.pump();
      await tester.pump();
      // A recognized command the library actually rejected also pops
      // the same pill the manual path would show for that exact
      // failure — same message, same widget.
      expect(
        find.widgetWithText(
          ConfirmationPill,
          'You haven\'t started "Dune" yet — try "start Dune" first.',
        ),
        findsOneWidget,
      );

      // A failure pauses the whole sequence for the pill's own full
      // lifetime (long enough to actually read it) before "start
      // Mockingbird" gets its turn.
      await tester.pump(const Duration(seconds: 3));
      // Its own success only needs its checkmark read, not a full pill
      // lifetime, before the loop finishes.
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.byIcon(Icons.check_circle), findsWidgets);

      // A mixed result (one failed, one didn't) still fades out and
      // clears itself on its own after a few seconds, same as a fully
      // successful list — and the typed sentence, already swapped out
      // the moment extraction succeeded, never comes back; a fresh,
      // empty CommandInput takes its place instead.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byType(InstructionRow), findsNothing);
      expect(find.text('finish Dune and start Mockingbird'), findsNothing);
      expect(find.byType(CommandInput), findsOneWidget);
    },
  );

  testWidgets('an unrecognized extracted line runs through the exact same '
      'unrecognized-command path a manual line would', (tester) async {
    await useDeviceSize(tester);
    // The AI returning "read Dune" would be its own extraction mistake
    // (not one of the five real commands) — [_runCommand] treats it
    // exactly like a manual typo: the parser's own suggestion pops
    // the pill, same as it would for a typed line.
    final ai = FakeAiCommandParser(commands: const ['read Dune']);
    final library = _newLibraryController();
    await tester.pumpWidget(_harness(HomePage(aiParser: ai), library));

    await tester.enterText(find.byType(TextField), 'I read some of Dune');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 800));

    expect(
      find.widgetWithText(
        ConfirmationPill,
        LogCommandParser.parse('read Dune').message,
      ),
      findsOneWidget,
    );

    // A failure pauses on its own pill for a full read (this is the
    // only line, so the loop itself doesn't finish until this
    // elapses), then the list fades out after its own further hold —
    // two full pill lifetimes altogether, plus the fade itself.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('read Dune', findRichText: true), findsNothing);

    // The typed sentence was already swapped out for the extracted
    // line the moment the AI returned it — once that line's own run
    // finishes (whether it succeeded or not), a fresh, empty
    // CommandInput comes back rather than the original text.
    expect(find.text('I read some of Dune'), findsNothing);
    expect(find.byType(CommandInput), findsOneWidget);
  });

  testWidgets(
    'an AI failure shows the error pill and never falls back to manual parsing',
    (tester) async {
      await useDeviceSize(tester);
      final ai = FakeAiCommandParser(
        failure: const AiCommandException(
          "You're offline — connect and try again.",
        ),
      );
      final library = _newLibraryController();
      await tester.pumpWidget(_harness(HomePage(aiParser: ai), library));

      await tester.enterText(find.byType(TextField), 'start Dune');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();

      expect(
        find.text("You're offline — connect and try again."),
        findsOneWidget,
      );
      // Rejected, not accepted — the raw text is still in the field.
      expect(find.text('start Dune'), findsOneWidget);
    },
  );

  testWidgets(
    'an empty extraction falls back to a single "gibberish" line, which '
    'fails the same way any other unrecognized line does',
    (tester) async {
      await useDeviceSize(tester);
      // The prompt asks the model itself to return ["gibberish"] rather than
      // [] when it finds nothing — this fake stands in for the rare
      // reply that doesn't comply, proving the defensive fallback in
      // `_runAi` covers it the exact same way.
      final ai = FakeAiCommandParser(commands: const []);
      final library = _newLibraryController();
      await tester.pumpWidget(_harness(HomePage(aiParser: ai), library));

      await tester.enterText(find.byType(TextField), 'good morning');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      expect(
        find.textContaining('gibberish', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(
          ConfirmationPill,
          LogCommandParser.parse('gibberish').message,
        ),
        findsOneWidget,
      );

      // A failure pauses on its own pill for a full read (this is the
      // only line, so the loop itself doesn't finish until this
      // elapses), then the list fades out after its own further hold —
      // two full pill lifetimes altogether, plus the fade itself.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('gibberish', findRichText: true),
        findsNothing,
      );

      // The typed sentence was already swapped out for the "gibberish"
      // fallback line — once its run finishes, a fresh, empty
      // CommandInput comes back rather than the original text.
      expect(find.text('good morning'), findsNothing);
      expect(find.byType(CommandInput), findsOneWidget);
    },
  );
}
