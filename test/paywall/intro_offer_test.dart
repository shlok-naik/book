import 'package:book/core/purchases/entitlements.dart';
import 'package:book/core/purchases/plan_controller.dart';
import 'package:book/core/purchases/purchases_service.dart';
import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/goals/presentation/goal_scope.dart';
import 'package:book/features/library/data/book_cache_repository.dart';
import 'package:book/features/library/data/google_book.dart';
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
import 'package:book/features/paywall/data/intro_offer_store.dart';
import 'package:book/features/paywall/presentation/pages/paywall_page.dart';
import 'package:book/features/shell/presentation/pages/root_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../support/fake_goals.dart';

/// The one-time intro paywall. The rule it exists to enforce is narrow
/// and easy to get wrong in the direction that annoys people: show it
/// once, to readers who have not already paid, and never again.

class _FakeIntroOfferStore extends IntroOfferStore {
  _FakeIntroOfferStore({this.seen = false});

  bool seen;
  int markSeenCalls = 0;

  @override
  Future<bool> hasSeen() async => seen;

  @override
  Future<void> markSeen() async {
    markSeenCalls++;
    seen = true;
  }
}

class _FakePurchasesService extends PurchasesService {
  _FakePurchasesService({required this.pro, this.failure});

  final bool pro;
  final PurchasesException? failure;

  @override
  Future<CustomerInfo> get customerInfo async {
    if (failure != null) throw failure!;
    return _customerInfo(pro: pro);
  }

  @override
  Future<Offering?> get currentOffering async => null;
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

// ---------------------------------------------------------------------
// The rest of the shell's dependencies, all inert: this file is about
// the popup, and every page behind it just has to mount without
// reaching for a network.

const _dune = Book(
  id: 'book-1',
  googleBooksId: 'gb-dune',
  title: 'Dune',
  author: 'Frank Herbert',
);

class _EmptyCache extends BookCacheRepository {
  @override
  Future<Book?> findByTitle(String title, {String? author}) async => _dune;

  @override
  Future<Book?> findByGoogleBooksId(String id) async => _dune;

  @override
  Future<Book> cache(GoogleBook volume) async => _dune;
}

class _EmptyUserBooks extends UserBookRepository {
  @override
  Future<List<LibraryBook>> fetchLibrary() async => const [];
}

class _EmptyEvents extends ReadingEventRepository {
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

Future<void> pumpShell(
  WidgetTester tester, {
  required IntroOfferStore introOffer,
  required PurchasesService purchases,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final library = _libraryController();
  addTearDown(library.dispose);
  final memory = MemoryController(repository: _EmptyMemories());
  addTearDown(memory.dispose);

  await tester.pumpWidget(
    GoalScope(
      controller: goalControllerFor(),
      child: LibraryScope(
        controller: library,
        child: MemoryScope(
          controller: memory,
          child: MaterialApp(
            theme: AppTheme.light,
            home: RootShell(introOffer: introOffer, purchases: purchases),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    addTearDown(() => PlanController.isPro.value = false);
  });

  testWidgets('shows once on a first launch, for a reader without pro', (
    tester,
  ) async {
    final store = _FakeIntroOfferStore();
    await pumpShell(
      tester,
      introOffer: store,
      purchases: _FakePurchasesService(pro: false),
    );

    expect(find.byType(PaywallPage), findsOneWidget);
    // Recorded as it opens, not as it closes — a reader who force-quits
    // while looking at it has still seen it.
    expect(store.markSeenCalls, 1);
  });

  testWidgets('stays away once the flag is set', (tester) async {
    final store = _FakeIntroOfferStore(seen: true);
    await pumpShell(
      tester,
      introOffer: store,
      purchases: _FakePurchasesService(pro: false),
    );

    expect(find.byType(PaywallPage), findsNothing);
    expect(store.markSeenCalls, 0);
  });

  testWidgets('never sells pro to a reader who already has it', (tester) async {
    final store = _FakeIntroOfferStore();
    await pumpShell(
      tester,
      introOffer: store,
      purchases: _FakePurchasesService(pro: true),
    );

    expect(find.byType(PaywallPage), findsNothing);
    // And the one chance is not burned either — nothing was shown.
    expect(store.markSeenCalls, 0);
  });

  testWidgets('fails closed when the entitlement cannot be read at all', (
    tester,
  ) async {
    final store = _FakeIntroOfferStore();
    await pumpShell(
      tester,
      introOffer: store,
      purchases: _FakePurchasesService(
        pro: false,
        failure: const PurchasesException("You're offline."),
      ),
    );

    // Unknown entitlements could mean a paying subscriber — showing
    // them a paywall is worse than missing one conversion.
    expect(find.byType(PaywallPage), findsNothing);
    expect(store.markSeenCalls, 0);
  });

  testWidgets('respects the debug pro override', (tester) async {
    PlanController.isPro.value = true;
    final store = _FakeIntroOfferStore();
    await pumpShell(
      tester,
      introOffer: store,
      purchases: _FakePurchasesService(pro: false),
    );

    expect(find.byType(PaywallPage), findsNothing);
  });

  testWidgets('can be dismissed, leaving the reader on the log tab', (
    tester,
  ) async {
    await pumpShell(
      tester,
      introOffer: _FakeIntroOfferStore(),
      purchases: _FakePurchasesService(pro: false),
    );

    expect(find.byType(PaywallPage), findsOneWidget);

    await tester.tap(find.byTooltip('close'));
    await tester.pumpAndSettle();

    expect(find.byType(PaywallPage), findsNothing);
    // The log page's own field is the proof the reader landed back in
    // the app rather than on another screen.
    expect(find.byType(TextField), findsOneWidget);
  });

  group('memory tab', () {
    int shownTab(WidgetTester tester) =>
        tester.widget<IndexedStack>(find.byType(IndexedStack)).index!;

    Future<void> tapMemory(WidgetTester tester) async {
      await tester.tap(find.bySemanticsLabel('Memory'));
      await tester.pumpAndSettle();
    }

    testWidgets('on the free plan, tapping it opens the paywall instead', (
      tester,
    ) async {
      await pumpShell(
        tester,
        introOffer: _FakeIntroOfferStore(seen: true),
        purchases: _FakePurchasesService(pro: false),
      );
      expect(shownTab(tester), 3);

      await tapMemory(tester);

      expect(find.byType(PaywallPage), findsOneWidget);
      expect(shownTab(tester), 3, reason: 'still on the add tab behind it');
    });

    testWidgets('a store that cannot be reached shows the paywall too', (
      tester,
    ) async {
      await pumpShell(
        tester,
        introOffer: _FakeIntroOfferStore(seen: true),
        purchases: _FakePurchasesService(
          pro: false,
          failure: const PurchasesException('offline'),
        ),
      );

      await tapMemory(tester);

      expect(find.byType(PaywallPage), findsOneWidget);
      expect(shownTab(tester), 3);
    });

    testWidgets('a real subscriber opens it, without a paywall', (
      tester,
    ) async {
      await pumpShell(
        tester,
        introOffer: _FakeIntroOfferStore(seen: true),
        purchases: _FakePurchasesService(pro: true),
      );

      await tapMemory(tester);

      expect(find.byType(PaywallPage), findsNothing);
      expect(shownTab(tester), 0);
    });

    testWidgets('the pro plan opens it directly', (tester) async {
      PlanController.isPro.value = true;
      await pumpShell(
        tester,
        introOffer: _FakeIntroOfferStore(seen: true),
        purchases: _FakePurchasesService(pro: false),
      );

      await tapMemory(tester);

      expect(find.byType(PaywallPage), findsNothing);
      expect(shownTab(tester), 0);
    });

    testWidgets('losing pro while on it moves the reader off it', (
      tester,
    ) async {
      PlanController.isPro.value = true;
      await pumpShell(
        tester,
        introOffer: _FakeIntroOfferStore(seen: true),
        purchases: _FakePurchasesService(pro: false),
      );
      await tapMemory(tester);
      expect(shownTab(tester), 0);

      PlanController.isPro.value = false;
      await tester.pumpAndSettle();

      expect(shownTab(tester), 3);
    });

    testWidgets('other tabs are never gated', (tester) async {
      await pumpShell(
        tester,
        introOffer: _FakeIntroOfferStore(seen: true),
        purchases: _FakePurchasesService(pro: false),
      );

      await tester.tap(find.bySemanticsLabel('Library'));
      await tester.pumpAndSettle();

      expect(find.byType(PaywallPage), findsNothing);
      expect(shownTab(tester), 2);
    });
  });
}
