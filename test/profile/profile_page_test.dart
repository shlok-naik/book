import 'package:book/core/purchases/entitlements.dart';
import 'package:book/core/purchases/purchases_service.dart';
import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/memory/data/memory_repository.dart';
import 'package:book/features/memory/domain/memory.dart';
import 'package:book/features/memory/presentation/controllers/memory_controller.dart';
import 'package:book/features/memory/presentation/memory_scope.dart';
import 'package:book/features/profile/presentation/pages/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// In-memory memories, fresh per test — `ProfilePage` kicks a `load()`
/// off in `initState`, which would otherwise hit the uninitialized
/// Supabase client.
class _InMemoryMemoryRepository extends MemoryRepository {
  _InMemoryMemoryRepository([List<Memory> seed = const []])
    : _memories = [...seed];

  final List<Memory> _memories;
  int _nextId = 0;

  @override
  Future<List<Memory>> fetchAll() async => _memories;

  @override
  Future<Memory> add({String? bookTitle, required String note}) async {
    final memory = Memory(
      id: 'memory-${_nextId++}',
      bookTitle: bookTitle,
      note: note,
      createdAt: DateTime.now(),
    );
    _memories.add(memory);
    return memory;
  }

  @override
  Future<void> delete(String id) async {
    _memories.removeWhere((memory) => memory.id == id);
  }
}

class FakePurchasesService extends PurchasesService {
  FakePurchasesService({
    this.info,
    this.infoError,
    this.restoreResult,
    this.restoreError,
  });

  CustomerInfo? info;
  PurchasesException? infoError;
  CustomerInfo? restoreResult;
  PurchasesException? restoreError;

  int customerCenterCalls = 0;
  int restoreCalls = 0;

  @override
  Future<CustomerInfo> get customerInfo async {
    final error = infoError;
    if (error != null) throw error;
    return info!;
  }

  @override
  Future<void> presentCustomerCenter() async {
    customerCenterCalls++;
  }

  @override
  Future<CustomerInfo> restore() async {
    restoreCalls++;
    final error = restoreError;
    if (error != null) throw error;
    return restoreResult!;
  }
}

CustomerInfo _fakeCustomerInfo({required bool pro}) {
  final entitlements = pro
      ? {
          Entitlements.cactusPro: const EntitlementInfo(
            Entitlements.cactusPro,
            true,
            true,
            '2024-01-01T00:00:00Z',
            '2024-01-01T00:00:00Z',
            PackageIds.yearly,
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

Future<void> pumpProfile(
  WidgetTester tester,
  FakePurchasesService purchases, {
  List<Memory> memories = const [],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MemoryScope(
        controller: MemoryController(
          repository: _InMemoryMemoryRepository(memories),
        ),
        child: ProfilePage(purchases: purchases),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the pro badge once customer info confirms it', (
    tester,
  ) async {
    await pumpProfile(
      tester,
      FakePurchasesService(info: _fakeCustomerInfo(pro: true)),
    );

    expect(find.text('cactus pro'), findsOneWidget);
    expect(find.text('free plan'), findsNothing);
  });

  testWidgets('shows the free plan state when there is no active entitlement', (
    tester,
  ) async {
    await pumpProfile(
      tester,
      FakePurchasesService(info: _fakeCustomerInfo(pro: false)),
    );

    expect(find.text('free plan'), findsOneWidget);
    expect(find.text('cactus pro'), findsNothing);
  });

  testWidgets('surfaces an error if customer info fails to load', (
    tester,
  ) async {
    await pumpProfile(
      tester,
      FakePurchasesService(
        infoError: const PurchasesException("You're offline."),
      ),
    );

    expect(find.text("You're offline."), findsOneWidget);
  });

  testWidgets(
    'tapping "manage subscription" opens Customer Center and refreshes',
    (tester) async {
      final purchases = FakePurchasesService(
        info: _fakeCustomerInfo(pro: false),
      );
      await pumpProfile(tester, purchases);

      // The reader upgrades while Customer Center is open — the next
      // refresh should pick that up.
      purchases.info = _fakeCustomerInfo(pro: true);

      await tester.tap(find.text('manage subscription'));
      await tester.pumpAndSettle();

      expect(purchases.customerCenterCalls, 1);
      expect(find.text('cactus pro'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping "restore purchases" re-checks entitlements from the restore result',
    (tester) async {
      final purchases = FakePurchasesService(
        info: _fakeCustomerInfo(pro: false),
        restoreResult: _fakeCustomerInfo(pro: true),
      );
      await pumpProfile(tester, purchases);

      await tester.tap(find.text('restore purchases'));
      await tester.pumpAndSettle();

      expect(purchases.restoreCalls, 1);
      expect(find.text('cactus pro'), findsOneWidget);
    },
  );

  group('memory', () {
    testWidgets('shows a hint when nothing has been remembered yet', (
      tester,
    ) async {
      await pumpProfile(
        tester,
        FakePurchasesService(info: _fakeCustomerInfo(pro: true)),
      );

      expect(find.textContaining('Nothing remembered yet'), findsOneWidget);
    });

    testWidgets('lists a saved memory, book title and note both visible', (
      tester,
    ) async {
      await pumpProfile(
        tester,
        FakePurchasesService(info: _fakeCustomerInfo(pro: true)),
        memories: [
          Memory(
            id: '1',
            bookTitle: 'Dune',
            note: 'loved the ending',
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
      );

      expect(find.text('Dune'), findsOneWidget);
      expect(find.text('loved the ending'), findsOneWidget);
    });

    testWidgets('tapping the close icon forgets that memory', (tester) async {
      await pumpProfile(
        tester,
        FakePurchasesService(info: _fakeCustomerInfo(pro: true)),
        memories: [
          Memory(
            id: '1',
            bookTitle: 'Dune',
            note: 'loved the ending',
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      expect(find.text('Dune'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Dune'), findsNothing);
      expect(find.textContaining('Nothing remembered yet'), findsOneWidget);
    });
  });
}
