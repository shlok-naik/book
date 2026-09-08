import 'package:book/core/auth/session_service.dart';
import 'package:book/core/purchases/entitlements.dart';
import 'package:book/core/purchases/purchases_service.dart';
import 'package:book/core/theme/app_theme.dart';
import 'package:book/core/theme/theme_controller.dart';
import 'package:book/features/settings/presentation/pages/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// The settings screen — everything the deleted profile page used to
/// carry, plus the account section that replaced onboarding's email
/// step. The store and the session are both faked; nothing here touches
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
  _FakeSession({this.anonymous = true, this.address});

  final bool anonymous;
  final String? address;

  @override
  bool get isSignedIn => true;

  @override
  bool get isAnonymous => anonymous;

  @override
  String? get email => address;
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
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: SettingsPage(purchases: purchases, session: session),
    ),
  );
  // One frame to mount, one for the entitlement fetch to resolve.
  await tester.pump();
  await tester.pump();
}

void main() {
  // ThemeController is a global, and the appearance test below moves it
  // — put it back so test order can't leak a forced theme into anything
  // that runs after.
  setUp(() {
    addTearDown(() => ThemeController.select(ThemeMode.system));
  });

  group('the subscription card', () {
    testWidgets('says "free plan" and offers the upgrade row', (tester) async {
      await pumpSettings(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(),
      );

      expect(find.text('free plan'), findsOneWidget);
      expect(find.text('get cactus pro'), findsOneWidget);
    });

    testWidgets('says "cactus pro" and drops the upgrade row once active', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: true)),
        session: _FakeSession(),
      );

      expect(find.text('cactus pro'), findsWidgets);
      expect(find.text('your subscription is active.'), findsOneWidget);
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

      await tester.tap(find.text('dark'));
      await tester.pumpAndSettle();

      expect(ThemeController.mode.value, ThemeMode.dark);
    });
  });

  group('account', () {
    testWidgets('an anonymous reader is offered a backup, not a sign-out', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(),
      );

      expect(find.text('back up with email'), findsOneWidget);
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
      expect(find.text('change email'), findsOneWidget);
      expect(find.text('back up with email'), findsNothing);
      // Signing out is not offered anywhere: for an anonymous reader
      // there is no credential to sign back in with, so it destroys a
      // library rather than protecting one.
      expect(find.text('sign out'), findsNothing);
    });

    testWidgets('the backup row opens the sheet in its "link" wording', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(),
      );

      await tester.tap(find.text('back up with email'));
      await tester.pumpAndSettle();

      expect(find.text('send code'), findsOneWidget);
      expect(
        find.textContaining('a way back to you on another device'),
        findsOneWidget,
      );
    });

    testWidgets('the change-email row opens the same sheet, reworded', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(anonymous: false, address: 'reader@example.com'),
      );

      await tester.tap(find.text('change email'));
      await tester.pumpAndSettle();

      // Same two-step sheet, same call underneath — only the copy knows
      // the difference.
      expect(find.text('send code'), findsOneWidget);
      expect(
        find.textContaining('only the address it answers to changes'),
        findsOneWidget,
      );
    });
  });

  group('about', () {
    testWidgets('names a version', (tester) async {
      await pumpSettings(
        tester,
        purchases: _FakePurchasesService(info: _customerInfo(pro: false)),
        session: _FakeSession(),
      );

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
}
