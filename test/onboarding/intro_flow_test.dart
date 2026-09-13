import 'package:book/core/theme/app_theme.dart';
import 'package:book/core/theme/theme_controller.dart';
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
import 'package:book/features/library/presentation/controllers/library_controller.dart';
import 'package:book/features/library/presentation/library_scope.dart';
import 'package:book/features/memory/data/memory_repository.dart';
import 'package:book/features/memory/domain/memory.dart';
import 'package:book/features/memory/presentation/controllers/memory_controller.dart';
import 'package:book/features/memory/presentation/memory_scope.dart';
import 'package:book/features/onboarding/data/onboarding_store.dart';
import 'package:book/features/onboarding/presentation/pages/add_book_tutorial_page.dart';
import 'package:book/features/onboarding/presentation/pages/finish_page.dart';
import 'package:book/features/onboarding/presentation/pages/founders_note_page.dart';
import 'package:book/features/onboarding/presentation/pages/natural_language_tutorial_page.dart';
import 'package:book/features/onboarding/presentation/pages/one_more_thing_page.dart';
import 'package:book/features/onboarding/presentation/pages/reading_goal_page.dart';
import 'package:book/features/onboarding/presentation/pages/tags_comments_tutorial_page.dart';
import 'package:book/features/onboarding/presentation/pages/theme_preference_page.dart';
import 'package:book/features/onboarding/presentation/pages/welcome_page.dart';
import 'package:book/features/shell/presentation/pages/root_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fake_goals.dart';

/// The intro, end to end. What this pins down is mostly what onboarding
/// *doesn't* do any more: it never asks for a name, an email or a
/// password, because the reader's anonymous account already exists by
/// the time the first frame renders. Backing that account up with an
/// email is offered later, in settings.

class _FakeOnboardingStore extends OnboardingStore {
  int markSeenCalls = 0;

  @override
  Future<bool> hasSeen() async => false;

  @override
  Future<void> markSeen() async => markSeenCalls++;
}

// Inert stand-ins for everything `RootShell` mounts once the intro hands
// over — this file is about the intro, not the app behind it.

class _EmptyCache extends BookCacheRepository {
  @override
  Future<Book?> findByTitle(String title, {String? author}) async => null;

  @override
  Future<Book?> findByGoogleBooksId(String id) async => null;
}

class _EmptyUserBooks extends UserBookRepository {
  @override
  Future<List<LibraryBook>> fetchLibrary() async => const [];
}

class _EmptyEvents extends ReadingEventRepository {
  @override
  Future<List<ReadingEvent>> fetchForYear(int year) async => const [];
}

class _EmptyMemories extends MemoryRepository {
  @override
  Future<List<Memory>> fetchAll() async => const [];
}

LibraryController _libraryController() {
  return LibraryController(
    lookup: BookLookupService(
      cache: _EmptyCache(),
      googleBooks: GoogleBooksApiClient(
        client: MockClient((_) async => http.Response('unused', 200)),
      ),
    ),
    userBooks: _EmptyUserBooks(),
    events: _EmptyEvents(),
  );
}

void useDeviceSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Wraps [child] in the scopes the app's composition root installs, so a
/// test that walks all the way through to `RootShell` can mount it.
Widget harness(WidgetTester tester, Widget child, {GoalController? goals}) {
  final library = _libraryController();
  addTearDown(library.dispose);
  final memory = MemoryController(repository: _EmptyMemories());
  addTearDown(memory.dispose);

  final goalController =
      goals ?? GoalController(repository: FakeGoalRepository());
  addTearDown(goalController.dispose);

  return GoalScope(
    controller: goalController,
    child: LibraryScope(
      controller: library,
      child: MemoryScope(
        controller: memory,
        child: MaterialApp(theme: AppTheme.light, home: child),
      ),
    ),
  );
}

Future<void> pumpIntro(WidgetTester tester, {GoalController? goals}) async {
  useDeviceSize(tester);
  await tester.pumpWidget(harness(tester, const WelcomePage(), goals: goals));
}

/// Fixed pumps rather than `pumpAndSettle`, because the tutorial pages
/// carry a marquee that scrolls forever — there is no "settled" frame
/// for it to wait for. Long enough to cover a route transition.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The welcome screen holds for two seconds, reveals its copy, then
/// waits another beat before the "start" button fades in — and the
/// button is inert until that fade has actually run.
Future<void> settleWelcome(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
  await settle(tester);
  await tester.pump(const Duration(milliseconds: 900));
  await settle(tester);
}

/// Taps a pill by its label. `ensureVisible` first, because the
/// half-sheet card scrolls: on a shorter viewport the button sits below
/// the fold, and tapping its off-screen centre hits nothing at all.
Future<void> tapPill(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester);
}

Future<void> start(WidgetTester tester) async {
  await settleWelcome(tester);
  await tapPill(tester, 'start');
}

Future<void> tapContinue(WidgetTester tester) => tapPill(tester, 'continue');

void main() {
  setUp(() {
    addTearDown(() => ThemeController.select(ThemeMode.system));
  });

  testWidgets('walks welcome → tutorials → look → finish, asking for nothing', (
    tester,
  ) async {
    await pumpIntro(tester);

    expect(find.text('cactus'), findsOneWidget);
    await start(tester);

    expect(find.byType(AddBookTutorialPage), findsOneWidget);
    await tapContinue(tester);

    // Straight after the free-tier commands: tags and comments, and the
    // DNF reason they're for.
    expect(find.byType(TagsCommentsTutorialPage), findsOneWidget);
    expect(find.textContaining('add tag <tag> <book>'), findsOneWidget);
    expect(find.textContaining('add comment <comment> <book>'), findsOneWidget);
    expect(
      find.textContaining('why you stopped', findRichText: true),
      findsOneWidget,
    );
    await tapContinue(tester);

    expect(find.byType(NaturalLanguageTutorialPage), findsOneWidget);
    await tapContinue(tester);

    expect(find.byType(ThemePreferencePage), findsOneWidget);
    await tapContinue(tester);

    expect(find.byType(ReadingGoalPage), findsOneWidget);
    await tapContinue(tester);

    expect(find.byType(OneMoreThingPage), findsOneWidget);
    await tapContinue(tester);

    // Stops here rather than tapping through to `FinishPage`: from this
    // screen "continue" opens the real one-time PRO paywall (see
    // `founders_note_paywall_test.dart`), which would reach for the
    // real RevenueCat SDK without a fake injected.
    expect(find.byType(FoundersNotePage), findsOneWidget);

    // Not one text field anywhere along the way — no name, no email, no
    // code to paste. That is the whole point of the rewrite.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('the look question drives the ThemeController settings uses', (
    tester,
  ) async {
    await pumpIntro(tester);
    await start(tester);
    await tapContinue(tester);
    await tapContinue(tester);
    await tapContinue(tester);

    expect(find.byType(ThemePreferencePage), findsOneWidget);
    expect(ThemeController.mode.value, ThemeMode.system);

    await tester.tap(find.byType(DropdownButtonFormField<ThemeMode>));
    await settle(tester);
    await tester.tap(find.text('🌙  dark').last);
    await settle(tester);

    // The same notifier the appearance rows in settings write to, so the
    // choice made here is one a reader can revisit rather than a
    // separate piece of state that drifts.
    expect(ThemeController.mode.value, ThemeMode.dark);
  });

  testWidgets('finishing records the flag and hands over to the app', (
    tester,
  ) async {
    useDeviceSize(tester);
    final store = _FakeOnboardingStore();

    await tester.pumpWidget(harness(tester, FinishPage(store: store)));
    await tester.pump();

    expect(store.markSeenCalls, 0);

    await tapPill(tester, "let's go");

    // Recorded on the way out, not on the way in: a reader who quits
    // halfway through the intro should get it again.
    expect(store.markSeenCalls, 1);
    expect(find.byType(RootShell), findsOneWidget);
    // The stack was replaced, not pushed — none of the intro is behind
    // the reader to pop back to.
    expect(find.byType(FinishPage), findsNothing);
  });

  Future<void> walkToGoal(WidgetTester tester, GoalController goals) async {
    await pumpIntro(tester, goals: goals);
    await start(tester);
    for (var i = 0; i < 4; i++) {
      await tapContinue(tester);
    }
    expect(find.byType(ReadingGoalPage), findsOneWidget);
  }

  testWidgets('the goal question saves through the GoalController the stats '
      'page reads', (tester) async {
    final repository = FakeGoalRepository();
    final goals = GoalController(repository: repository);
    await walkToGoal(tester, goals);

    final plus = find.byIcon(Icons.add);
    await tester.ensureVisible(plus);
    await tester.tap(plus);
    await settle(tester);
    expect(find.text('13'), findsOneWidget);
    await tapContinue(tester);

    expect(repository.saved, [13]);
    expect(goals.goal, 13);
    expect(find.byType(OneMoreThingPage), findsOneWidget);
  });

  testWidgets('the goal question can be skipped without saving anything', (
    tester,
  ) async {
    final repository = FakeGoalRepository();
    await walkToGoal(tester, GoalController(repository: repository));

    await tapPill(tester, 'skip for now');

    expect(repository.saved, isEmpty);
    expect(find.byType(OneMoreThingPage), findsOneWidget);
  });
}
