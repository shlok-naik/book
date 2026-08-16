import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:book/main.dart';

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
    await tester.pump();
  }

  testWidgets('Log page is the default view, with a text box that confirms on submit',
      (WidgetTester tester) async {
    await useDeviceSize(tester);
    await tester.pumpWidget(const BookApp());

    expect(find.byType(TextField), findsOneWidget);

    await submit(tester, 'start Dune');
    expect(find.text('Started "Dune"'), findsOneWidget);
  });

  testWidgets('recognizes update, finish, and rate commands',
      (WidgetTester tester) async {
    await useDeviceSize(tester);
    await tester.pumpWidget(const BookApp());

    await submit(tester, 'update Dune 120');
    expect(find.text('"Dune" — pg 120'), findsOneWidget);

    await submit(tester, 'finish Dune');
    expect(find.text('Finished "Dune"'), findsOneWidget);

    await submit(tester, 'rate Dune 5 stars');
    expect(find.text('"Dune" — 5★'), findsOneWidget);
  });

  testWidgets('Streaks page is reachable and grouped by month',
      (WidgetTester tester) async {
    await useDeviceSize(tester);
    await tester.pumpWidget(const BookApp());
    await goToStreaksPage(tester);

    expect(find.text('january'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
