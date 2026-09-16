import 'package:book/core/ai/ai_command_parser.dart';
import 'package:book/core/purchases/plan_controller.dart';
import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/goals/presentation/goal_scope.dart';
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
import 'package:book/features/logging/presentation/pages/home_page.dart';
import 'package:book/features/logging/presentation/widgets/command_input.dart';
import 'package:book/features/logging/presentation/widgets/confirmation_pill.dart';
import 'package:book/features/memory/data/memory_repository.dart';
import 'package:book/features/memory/domain/memory.dart';
import 'package:book/features/memory/presentation/controllers/memory_controller.dart';
import 'package:book/features/memory/presentation/memory_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fake_goals.dart';

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
  Future<UserBook> saveProgress({
    required String userBookId,
    required int currentPage,
    required bool finished,
    DateTime? finishedAt,
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

  /// What the last call actually received — lets a test assert on the
  /// context `HomePage` built, without a real edge function to inspect
  /// the request it would have sent.
  List<String>? lastLibraryTitles;
  List<({String? title, String note})>? lastMemoryNotes;

  @override
  Future<List<String>> extractCommands(
    String message, {
    List<String> libraryTitles = const [],
    List<({String? title, String note})> memoryNotes = const [],
  }) async {
    extractCommandsCalls++;
    lastLibraryTitles = libraryTitles;
    lastMemoryNotes = memoryNotes;
    if (failure != null) throw failure!;
    return commands;
  }
}

/// In-memory `MemoryRepository` stand-in — `HomePage` (and `MemoryScope`
/// more generally) needs one above it whether or not a given test
/// exercises the memory feature. Genuinely stateful, not a stub
/// returning `const []`: `HomePage.initState`'s own `load()` runs a real
/// `refresh()` against this on mount, and a test that pre-seeded a
/// memory through the controller (to check `recommend`'s context, say)
/// needs that fetch to see it rather than clobber it with an empty list.
class _InMemoryMemoryRepository extends MemoryRepository {
  final List<Memory> _memories = [];
  int _nextId = 0;

  @override
  Future<List<Memory>> fetchAll() async => [..._memories];

  @override
  Future<Memory> add({String? bookTitle, required String note}) async {
    final memory = Memory(
      id: 'memory-${_nextId++}',
      bookTitle: bookTitle,
      note: note,
      createdAt: DateTime.now(),
    );
    _memories.insert(0, memory);
    return memory;
  }

  @override
  Future<void> delete(String id) async {
    _memories.removeWhere((memory) => memory.id == id);
  }
}

Widget _harness(
  Widget child,
  LibraryController library, {
  MemoryController? memory,
}) {
  return GoalScope(
    controller: goalControllerFor(),
    child: MaterialApp(
      theme: AppTheme.light,
      home: LibraryScope(
        controller: library,
        child: MemoryScope(
          controller:
              memory ??
              MemoryController(repository: _InMemoryMemoryRepository()),
          child: child,
        ),
      ),
    ),
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

  /// Submits [text] and lets the extraction and every line resolve —
  /// without running the field's accept animation to its end.
  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  testWidgets('a sentence runs its actions and says what happened in words, '
      'never showing the commands', (tester) async {
    await useDeviceSize(tester);
    final ai = FakeAiCommandParser(
      commands: const ['start Dune', 'update Dune 120'],
    );
    final library = _newLibraryController();
    await tester.pumpWidget(_harness(HomePage(aiParser: ai), library));

    await send(tester, "I started Dune and I'm on page 120");

    expect(ai.extractCommandsCalls, 1);
    expect(library.inProgress.single.currentPage, 120);
    // The field never leaves, so neither does the keyboard.
    expect(find.byType(CommandInput), findsOneWidget);
    expect(find.textContaining('start Dune', findRichText: true), findsNothing);
    expect(
      find.textContaining('update Dune', findRichText: true),
      findsNothing,
    );
    expect(
      find.widgetWithText(
        ConfirmationPill,
        'Started "Dune" · On page 120 of "Dune"',
      ),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byType(CommandInput), findsOneWidget);
    expect(find.text("I started Dune and I'm on page 120"), findsNothing);
    expect(tester.testTextInput.hasAnyClients, isTrue);
  });

  testWidgets('a failing action does not stop the rest, and both outcomes are '
      'said together', (tester) async {
    await useDeviceSize(tester);
    final ai = FakeAiCommandParser(
      commands: const ['rate Dune 9', 'start Mockingbird'],
    );
    final library = _newLibraryController();
    await tester.pumpWidget(_harness(HomePage(aiParser: ai), library));

    await send(tester, 'rate Dune 9 and start Mockingbird');

    // Successes first, then what failed — in one pill.
    expect(library.inProgress, hasLength(1));
    expect(
      find.textContaining(RegExp(r'^Started ".+" · Rate 0\.5–5 stars\.$')),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('a line that is not a command is just not understood — no '
      'command syntax suggested', (tester) async {
    await useDeviceSize(tester);
    final ai = FakeAiCommandParser(commands: const ['read Dune']);
    final library = _newLibraryController();
    await tester.pumpWidget(_harness(HomePage(aiParser: ai), library));

    await send(tester, 'I read some of Dune');

    expect(
      find.widgetWithText(ConfirmationPill, "Didn't catch that."),
      findsOneWidget,
    );
    // Rejected: the sentence stays in the field to fix.
    expect(find.text('I read some of Dune'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('an empty extraction is not understood either', (tester) async {
    await useDeviceSize(tester);
    final ai = FakeAiCommandParser(commands: const []);
    final library = _newLibraryController();
    await tester.pumpWidget(_harness(HomePage(aiParser: ai), library));

    await send(tester, 'good morning');

    expect(
      find.widgetWithText(ConfirmationPill, "Didn't catch that."),
      findsOneWidget,
    );
    expect(find.textContaining('gibberish', findRichText: true), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
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

  group('remember and recommend', () {
    testWidgets('remember saves a memory on cactus pro', (tester) async {
      await useDeviceSize(tester);
      final ai = FakeAiCommandParser(
        commands: const ['remember Dune :: loved the ending'],
      );
      final library = _newLibraryController();
      final memory = MemoryController(repository: _InMemoryMemoryRepository());
      await tester.pumpWidget(
        _harness(HomePage(aiParser: ai), library, memory: memory),
      );

      await tester.enterText(find.byType(TextField), 'loved the ending!');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();

      expect(
        find.widgetWithText(ConfirmationPill, 'Remembered that about "Dune"'),
        findsOneWidget,
      );
      expect(memory.memories, hasLength(1));
      expect(memory.memories.single.bookTitle, 'Dune');
      expect(memory.memories.single.note, 'loved the ending');

      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('recommend shows the pick without touching the shelf or '
        'the memory list', (tester) async {
      await useDeviceSize(tester);
      final ai = FakeAiCommandParser(
        commands: const [
          'recommend Circe :: another morally complex retelling',
        ],
      );
      final library = _newLibraryController();
      final memory = MemoryController(repository: _InMemoryMemoryRepository());
      await tester.pumpWidget(
        _harness(HomePage(aiParser: ai), library, memory: memory),
      );

      await tester.enterText(
        find.byType(TextField),
        'recommend me something like Dune',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();

      expect(
        find.widgetWithText(
          ConfirmationPill,
          '"Circe" — another morally complex retelling',
        ),
        findsOneWidget,
      );
      expect(library.inProgress, isEmpty);
      expect(library.finished, isEmpty);
      expect(memory.memories, isEmpty);

      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('both are refused on the free plan, with an upgrade message', (
      tester,
    ) async {
      await useDeviceSize(tester);
      PlanController.isPro.value = false;
      final library = _newLibraryController();
      final memory = MemoryController(repository: _InMemoryMemoryRepository());
      await tester.pumpWidget(_harness(HomePage(), library, memory: memory));

      // The free plan only ever runs `LogCommandParser` on the whole
      // typed line — no AI involved — so the exact `::` syntax has to
      // be typed directly to reach `_applyToLibrary`'s pro gate at
      // all.
      await tester.enterText(
        find.byType(TextField),
        'remember Dune :: loved the ending',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();

      expect(
        find.widgetWithText(ConfirmationPill, 'Memories need cactus pro.'),
        findsOneWidget,
      );
      expect(memory.memories, isEmpty);
    });

    testWidgets('sends the shelf and memory notes as recommend context', (
      tester,
    ) async {
      await useDeviceSize(tester);
      final ai = FakeAiCommandParser(commands: const ['gibberish']);
      final library = _newLibraryController();
      await library.startBook('Dune');
      final memory = MemoryController(repository: _InMemoryMemoryRepository());
      await memory.remember(bookTitle: 'Circe', note: 'loved the retelling');
      await tester.pumpWidget(
        _harness(HomePage(aiParser: ai), library, memory: memory),
      );

      await tester.enterText(find.byType(TextField), 'recommend me a book');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();

      expect(ai.lastLibraryTitles, contains('Dune'));
      expect(
        ai.lastMemoryNotes,
        contains((title: 'Circe', note: 'loved the retelling')),
      );

      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });
  });
}
