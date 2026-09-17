import 'package:book/core/network/connectivity_controller.dart';
import 'package:book/core/offline/offline_store.dart';
import 'package:book/core/offline/pending_write.dart';
import 'package:book/core/offline/pending_write_queue.dart';
import 'package:book/core/offline/sync_coordinator.dart';
import 'package:book/core/offline/sync_scope.dart';
import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/settings/presentation/widgets/settings_header.dart';
import 'package:book/features/shell/presentation/widgets/top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The offline mark every page header carries, just left of its icon.

class _NeverExecutor implements PendingWriteExecutor {
  @override
  Future<ReplayOutcome> execute(PendingWrite write) async =>
      ReplayOutcome.unreachable;
}

Future<void> pumpHeader(
  WidgetTester tester, {
  required Widget header,
  PendingWriteQueue? queue,
}) async {
  Widget page = Scaffold(body: SafeArea(child: header));
  if (queue != null) {
    page = SyncScope(
      queue: queue,
      coordinator: SyncCoordinator(queue: queue, executor: _NeverExecutor()),
      child: page,
    );
  }
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: page));
}

void main() {
  tearDown(ConnectivityController.reset);

  const offlineMark = ValueKey('offline-indicator');
  const syncingMark = ValueKey('syncing-indicator');

  testWidgets('online with nothing waiting, it takes no room at all', (
    tester,
  ) async {
    await pumpHeader(tester, header: const TopBar(title: 'add'));
    expect(find.byKey(offlineMark), findsNothing);
    expect(find.byKey(syncingMark), findsNothing);
  });

  testWidgets('offline, it sits just left of the profile avatar', (
    tester,
  ) async {
    await pumpHeader(tester, header: const TopBar(title: 'add'));

    ConnectivityController.debugSetOffline(true);
    await tester.pump();

    final mark = tester.getCenter(find.byKey(offlineMark));
    final avatar = tester.getCenter(find.byIcon(Icons.account_circle_outlined));
    expect(mark.dx, lessThan(avatar.dx));
    expect((mark.dy - avatar.dy).abs(), lessThan(1));

    ConnectivityController.debugSetOffline(false);
    await tester.pump();
    expect(find.byKey(offlineMark), findsNothing);
  });

  testWidgets('pages pushed from settings carry it too', (tester) async {
    ConnectivityController.debugSetOffline(true);
    await pumpHeader(tester, header: const SettingsHeader(title: 'settings'));
    expect(find.byKey(offlineMark), findsOneWidget);
  });

  testWidgets('tapping it explains what still works, and how much is waiting', (
    tester,
  ) async {
    final queue = PendingWriteQueue(store: MemoryOfflineStore());
    await queue.enqueue(
      PendingUpdate(
        id: 'a',
        createdAt: DateTime.utc(2026),
        table: 'user_books',
        rowId: 'r1',
        values: const {'rating': 4},
      ),
    );
    ConnectivityController.debugSetOffline(true);
    await pumpHeader(
      tester,
      header: const TopBar(title: 'add'),
      queue: queue,
    );

    await tester.tap(find.byKey(offlineMark));
    await tester.pumpAndSettle();

    expect(find.text("you're offline"), findsOneWidget);
    expect(find.text('1 change waiting to sync'), findsOneWidget);
  });

  testWidgets('back online with changes still waiting, it shows syncing', (
    tester,
  ) async {
    final queue = PendingWriteQueue(store: MemoryOfflineStore());
    await queue.enqueue(
      PendingUpdate(
        id: 'a',
        createdAt: DateTime.utc(2026),
        table: 'user_books',
        rowId: 'r1',
        values: const {'rating': 4},
      ),
    );
    await pumpHeader(
      tester,
      header: const TopBar(title: 'add'),
      queue: queue,
    );

    expect(find.byKey(syncingMark), findsOneWidget);
    expect(find.byKey(offlineMark), findsNothing);
  });
}
