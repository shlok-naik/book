import 'package:book/core/auth/session_service.dart';
import 'package:book/core/platform/app_icon.dart';
import 'package:book/core/platform/app_icon_channel.dart';
import 'package:book/core/platform/app_icon_controller.dart';
import 'package:book/core/purchases/entitlements.dart';
import 'package:book/core/purchases/purchases_service.dart';
import 'package:book/core/theme/app_theme.dart';
import 'package:book/core/theme/text_size_controller.dart';
import 'package:book/core/theme/theme_controller.dart';
import 'package:book/features/goals/presentation/controllers/goal_controller.dart';
import 'package:book/features/goals/presentation/goal_scope.dart';
import 'package:book/features/logging/domain/command_catalog.dart';
import 'package:book/features/logging/presentation/parser_mode_controller.dart';
import 'package:book/features/paywall/presentation/pages/paywall_page.dart';
import 'package:book/features/settings/data/profile_repository.dart';
import 'package:book/features/settings/presentation/pages/commands_page.dart';
import 'package:book/features/settings/presentation/pages/customisation_page.dart';
import 'package:book/features/settings/presentation/pages/settings_page.dart';
import 'package:book/features/shell/presentation/start_page_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_goals.dart';

/// The settings screen — how the app behaves, and nothing about who the
/// reader is: the membership card and the profile rows live on the profile
/// screen now (`test/profile/profile_page_test.dart`). The store, the
/// session and the profile repository are all faked; nothing here touches
/// RevenueCat or Supabase.

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
  @override
  bool get isSignedIn => true;

  @override
  bool get isAnonymous => true;

  @override
  String? get email => null;

  @override
  String? get userId => 'fake-user-id';
}

/// Never touches Supabase — [joinedAt] is what `fetchJoinedAt` returns,
/// the same role `FakePurchasesService` plays for RevenueCat.
class _FakeProfileRepository extends ProfileRepository {
  _FakeProfileRepository({DateTime? joinedAt})
    : _future = Future.value(joinedAt);

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

  group('starting page', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      addTearDown(StartPageController.reset);
    });

    testWidgets('offers add, search and library, add ticked by default', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(),
      );

      await scrollTo(tester, find.text('starting page'));
      expect(StartPageController.page.value, StartPage.add);

      await scrollTo(tester, find.text('search').last);
      await tester.tap(find.text('search').last);
      await tester.pumpAndSettle();

      expect(StartPageController.page.value, StartPage.search);
    });
  });

  group('text size', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      addTearDown(TextSizeController.reset);
    });

    testWidgets('standard by default, and larger is one tap', (tester) async {
      await pumpSettings(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(),
      );

      await scrollTo(tester, find.text('text size'));
      expect(TextSizeController.size.value, TextSize.standard);

      final largest = find.byKey(const ValueKey('text-size-largest'));
      await scrollTo(tester, largest);
      await tester.tap(largest);
      await tester.pumpAndSettle();

      expect(TextSizeController.size.value, TextSize.largest);
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
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      addTearDown(ParserModeController.reset);
    });

    testWidgets('picks the parser instead of pretending a plan', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(),
      );

      // `flutter test` runs in debug, so this section is compiled in
      // here by definition; a release build tree-shakes it away.
      final classic = find.byKey(const ValueKey('parser-mode-classic'));
      await tester.scrollUntilVisible(classic, 200);
      await tester.ensureVisible(classic);
      await tester.pumpAndSettle();
      expect(find.text('pretend plan'), findsNothing);
      expect(find.text('beta parser'), findsOneWidget);
      expect(find.text('pro ai'), findsOneWidget);
      // Free readers start on the beta parser; classic is a debug choice.
      expect(ParserModeController.effective(offline: false), ParserMode.beta);

      await tester.tap(classic);
      await tester.pumpAndSettle();

      expect(ParserModeController.chosen.value, ParserMode.classic);
      expect(
        ParserModeController.effective(offline: false),
        ParserMode.classic,
      );
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
