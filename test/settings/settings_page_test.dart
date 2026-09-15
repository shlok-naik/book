import 'dart:async';

import 'package:book/core/auth/session_service.dart';
import 'package:book/core/platform/app_icon.dart';
import 'package:book/core/platform/app_icon_channel.dart';
import 'package:book/core/platform/app_icon_controller.dart';
import 'package:book/core/purchases/entitlements.dart';
import 'package:book/core/purchases/purchases_service.dart';
import 'package:book/core/theme/app_theme.dart';
import 'package:book/core/theme/theme_controller.dart';
import 'package:book/features/goals/presentation/controllers/goal_controller.dart';
import 'package:book/features/goals/presentation/goal_scope.dart';
import 'package:book/features/logging/domain/command_catalog.dart';
import 'package:book/features/paywall/presentation/pages/paywall_page.dart';
import 'package:book/features/settings/data/profile_repository.dart';
import 'package:book/features/settings/presentation/pages/commands_page.dart';
import 'package:book/features/settings/presentation/pages/customisation_page.dart';
import 'package:book/features/settings/presentation/pages/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../support/fake_goals.dart';

/// The settings screen — everything the deleted profile page used to
/// carry, plus the membership card that replaced onboarding's email
/// step (and the settings screen's own former "account" section). The
/// store, the session, and the profile repository are all faked;
/// nothing here touches RevenueCat or Supabase.

class _FakePurchasesService extends PurchasesService {
  _FakePurchasesService({required this.info});

  final CustomerInfo info;

  int customerCenterCalls = 0;
  int restoreCalls = 0;

  @override
  Future<CustomerInfo> get customerInfo async => info;

  @override
  Future<void> presentCustomerCenter() async => customerCenterCalls++;

  @override
  Future<CustomerInfo> restore() async {
    restoreCalls++;
    return info;
  }
}

class _FakeSession extends SessionService {
  _FakeSession({this.anonymous = true, this.address});

  final bool anonymous;
  final String? address;

  @override
  bool get isSignedIn => true;

  @override
  bool get isAnonymous => anonymous;

  @override
  String? get email => address;

  @override
  String? get userId => 'fake-user-id';
}

/// Never touches Supabase — [joinedAt] is what `fetchJoinedAt` returns,
/// the same role `FakePurchasesService` plays for RevenueCat.
class _FakeProfileRepository extends ProfileRepository {
  _FakeProfileRepository({DateTime? joinedAt})
    : _future = Future.value(joinedAt);

  /// Never resolves — for the one test that needs to catch the card
  /// mid-load, before `fetchJoinedAt` has answered at all.
  _FakeProfileRepository.pending() : _future = Completer<DateTime?>().future;

  final Future<DateTime?> _future;

  @override
  Future<DateTime?> fetchJoinedAt(String userId) => _future;
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

Future<void> pumpSettings(
  WidgetTester tester, {
  required PurchasesService purchases,
  required SessionService session,
  ProfileRepository? profileRepository,
  GoalController? goals,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    GoalScope(
      controller: goals ?? goalControllerFor(),
      child: MaterialApp(
        theme: AppTheme.light,
        home: SettingsPage(
          purchases: purchases,
          session: session,
          profileRepository: profileRepository ?? _FakeProfileRepository(),
        ),
      ),
    ),
  );
  // One frame to mount, one for the entitlement fetch to resolve.
  await tester.pump();
  await tester.pump();
}

/// Scrolls the settings list until [finder] is built and on screen — its
/// rows are built lazily, so one below the fold doesn't exist to
/// `ensureVisible` until the list has scrolled near it.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  // ThemeController is a global, and the appearance test below moves it
  // — put it back so test order can't leak a forced theme into anything
  // that runs after.
  setUp(() {
    addTearDown(() => ThemeController.select(ThemeMode.system));
    // AppIconController is a global too — restore the real channel and
    // its light default so a fake from one test can't leak into the
    // next.
    addTearDown(() {
      AppIconController.channel = const AppIconChannel();
      AppIconController.current.value = AppIcon.originalLight;
    });
  });

  group('the cactus pro section', () {
    testWidgets('offers the upgrade row on the free plan', (tester) async {
      await pumpSettings(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(),
      );

      expect(find.text('get cactus pro'), findsOneWidget);
    });

    testWidgets('drops the upgrade row once pro is active', (tester) async {
      await pumpSettings(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: true)),
        session: _FakeSession(),
      );

      expect(find.text('cactus pro'), findsWidgets);
      // Nothing left to sell to a reader who already bought.
      expect(find.text('get cactus pro'), findsNothing);
    });

    testWidgets('manage and restore both reach the store', (tester) async {
      final purchases = _FakePurchasesService(info: _customerInfo(pro: true));
      await pumpSettings(tester, purchases: purchases, session: _FakeSession());

      await tester.tap(find.text('manage subscription'));
      await tester.pumpAndSettle();
      expect(purchases.customerCenterCalls, 1);

      await tester.tap(find.text('restore purchases'));
      await tester.pumpAndSettle();
      expect(purchases.restoreCalls, 1);
    });
  });

  group('appearance', () {
    testWidgets('picking a mode moves ThemeController', (tester) async {
      await pumpSettings(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(),
      );

      expect(ThemeController.mode.value, ThemeMode.system);

      await scrollTo(tester, find.text('dark'));
      await tester.tap(find.text('dark'));
      await tester.pumpAndSettle();

      expect(ThemeController.mode.value, ThemeMode.dark);
    });
  });

  group('commands', () {
    testWidgets('the help row opens the commands reference', (tester) async {
      await pumpSettings(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(),
      );
      final row = find.text('commands');
      await scrollTo(tester, row);

      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(find.byType(CommandsPage), findsOneWidget);
      // The new syntax is listed, and the old one is gone.
      final move = find.text('move <book> <shelf>');
      await scrollTo(tester, move);
      expect(move, findsOneWidget);
      final addTag = find.text('add tag <tag> <book>');
      await scrollTo(tester, addTag);
      expect(addTag, findsOneWidget);
      final addComment = find.text('add comment <comment> <book>');
      await scrollTo(tester, addComment);
      expect(addComment, findsOneWidget);
      expect(find.textContaining('add <book> tbr'), findsNothing);
    });

    testWidgets('lists every command in the catalog', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const CommandsPage()),
      );

      for (final command in CommandCatalog.all) {
        await scrollTo(tester, find.text(command.syntax));
        expect(find.text(command.syntax), findsOneWidget);
      }
    });
  });

  group('customisation', () {
    Finder row() => find.text('themes and icons');

    testWidgets('a free reader sees it faded and reaches the paywall', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(),
      );
      await scrollTo(tester, row());

      final opacity = tester.widget<Opacity>(
        find.ancestor(of: row(), matching: find.byType(Opacity)).first,
      );
      expect(opacity.opacity, lessThan(1.0));

      await tester.tap(row());
      await tester.pumpAndSettle();

      expect(find.byType(PaywallPage), findsOneWidget);
      expect(find.byType(CustomisationPage), findsNothing);
    });

    testWidgets('a pro reader opens the customisation page', (tester) async {
      await pumpSettings(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: true)),
        session: _FakeSession(),
      );
      await scrollTo(tester, row());
      expect(
        find.ancestor(of: row(), matching: find.byType(Opacity)),
        findsNothing,
      );

      await tester.tap(row());
      await tester.pumpAndSettle();

      expect(find.byType(CustomisationPage), findsOneWidget);
    });
  });

  group('membership card', () {
    testWidgets('an anonymous reader is offered a backup, not a sign-out', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(),
      );

      expect(find.text('add email'), findsOneWidget);
      // Signing out of an anonymous account would strand its shelf
      // behind a uid nobody can authenticate as again.
      expect(find.text('sign out'), findsNothing);
      expect(
        find.textContaining('Your shelf lives on this device only'),
        findsOneWidget,
      );
    });

    testWidgets('a linked reader sees their address and can change it', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(anonymous: false, address: 'reader@example.com'),
      );

      expect(find.text('reader@example.com'), findsOneWidget);
      expect(find.text('add email'), findsNothing);
      // Signing out is not offered anywhere: for an anonymous reader
      // there is no credential to sign back in with, so it destroys a
      // library rather than protecting one.
      expect(find.text('sign out'), findsNothing);
    });

    testWidgets(
      'tapping the backup line opens the email sheet in its "link" wording',
      (tester) async {
        await pumpSettings(
          tester,
          purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
          session: _FakeSession(),
        );

        await tester.tap(find.text('add email'));
        await tester.pumpAndSettle();

        expect(find.text('send code'), findsOneWidget);
        expect(
          find.textContaining('a way back to you on another device'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'tapping the address opens the same sheet, reworded to change it',
      (tester) async {
        await pumpSettings(
          tester,
          purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
          session: _FakeSession(
            anonymous: false,
            address: 'reader@example.com',
          ),
        );

        await tester.tap(find.text('reader@example.com'));
        await tester.pumpAndSettle();

        // Same two-step sheet, same call underneath — only the copy
        // knows the difference.
        expect(find.text('send code'), findsOneWidget);
        expect(
          find.textContaining('only the address it answers to changes'),
          findsOneWidget,
        );
      },
    );

    testWidgets('shows no PRO badge for a free reader', (tester) async {
      await pumpSettings(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(),
      );
      expect(find.text('PRO'), findsNothing);
    });

    testWidgets('shows the PRO badge for a paying reader', (tester) async {
      await pumpSettings(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: true)),
        session: _FakeSession(),
      );
      expect(find.text('PRO'), findsOneWidget);
    });

    testWidgets('shows when the account was created', (tester) async {
      await pumpSettings(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(),
        profileRepository: _FakeProfileRepository(
          // Noon UTC, not midnight — safely the same calendar day once
          // `_dateLabel` converts it to local, regardless of which
          // timezone this test happens to run in.
          joinedAt: DateTime.utc(2026, 3, 5, 12),
        ),
      );

      expect(find.text('member since'), findsOneWidget);
      expect(find.text('3.5.26'), findsOneWidget);
    });

    testWidgets(
      'shows a loading placeholder rather than growing once the date lands',
      (tester) async {
        await pumpSettings(
          tester,
          purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
          session: _FakeSession(),
          profileRepository: _FakeProfileRepository.pending(),
        );

        // "member since" is never conditional on the fetch — only the
        // value below it is — so the card's height is already settled
        // here, before `fetchJoinedAt` has even answered.
        expect(find.text('member since'), findsOneWidget);
        expect(find.text('···'), findsOneWidget);
      },
    );

    testWidgets('shows a dash when the join date could not be loaded', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(),
        profileRepository: _FakeProfileRepository(),
      );

      expect(find.text('member since'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
    });
  });

  group('about', () {
    testWidgets('names a version', (tester) async {
      await pumpSettings(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(),
      );

      // The membership card at the top pushes this section below the
      // fold on this test viewport — same reason the debug section's
      // own test scrolls first.
      await tester.scrollUntilVisible(find.text('version'), 200);
      expect(find.text('version'), findsOneWidget);
      expect(find.text('open source licenses'), findsOneWidget);
    });
  });

  group('debug', () {
    testWidgets('the plan override is present under kDebugMode', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(),
      );

      // `flutter test` runs in debug, so this section is compiled in
      // here by definition — the assertion that matters is the reverse
      // one the analyzer enforces for us: it sits behind `kDebugMode`,
      // so a release build tree-shakes it away entirely.
      await tester.scrollUntilVisible(find.text('pretend plan'), 200);
      expect(find.text('pretend plan'), findsOneWidget);
    });
  });

  testWidgets('the yearly goal row shows the goal and edits it', (
    tester,
  ) async {
    final goals = goalControllerFor(goal: 20);
    await pumpSettings(
      tester,
      purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
      session: _FakeSession(),
      goals: goals,
    );
    await tester.pump();

    expect(find.text('yearly goal'), findsOneWidget);
    expect(find.text('20 books'), findsOneWidget);

    await tester.tap(find.text('yearly goal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('remove goal'));
    await tester.pumpAndSettle();

    expect(goals.goal, isNull);
    expect(find.text('not set'), findsOneWidget);
  });
}
