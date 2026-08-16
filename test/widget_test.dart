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
    // Let the strike-through/checkmark animation finish and the field
    // reset, so the next submit() can find the TextField again.
    await tester.pump(const Duration(milliseconds: 1400));
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

  testWidgets(
      'shows a strikethrough + checkmark in place of the field right after '
      'a valid command, then resets it', (WidgetTester tester) async {
    await useDeviceSize(tester);
    await tester.pumpWidget(const BookApp());

    await tester.enterText(find.byType(TextField), 'start Dune');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('start Dune'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1400));
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('keeps the field and shakes for an unrecognized command',
      (WidgetTester tester) async {
    await useDeviceSize(tester);
    await tester.pumpWidget(const BookApp());

    await tester.enterText(find.byType(TextField), 'gibberish');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.textContaining('Not recognized'), findsOneWidget);
  });

  testWidgets(
      'clears the confirmation pill on its own after a few seconds, for '
      'both success and error', (WidgetTester tester) async {
    await useDeviceSize(tester);
    await tester.pumpWidget(const BookApp());

    await submit(tester, 'start Dune');
    expect(find.text('Started "Dune"'), findsOneWidget);
    // Let the lifetime timer fire, then pump incrementally so the
    // fade-out animation it kicks off actually ticks to completion.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Started "Dune"'), findsNothing);

    await tester.enterText(find.byType(TextField), 'gibberish');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.textContaining('Not recognized'), findsOneWidget);
    // Let the lifetime timer fire, then pump incrementally so the
    // fade-out animation it kicks off actually ticks to completion.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.textContaining('Not recognized'), findsNothing);
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
