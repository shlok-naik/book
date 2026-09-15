import 'dart:async';

import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/logging/presentation/widgets/command_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Regression: a handler that threw left the field's busy flag set, so it
  // stayed read-only — on the add tab, for the rest of the session.
  testWidgets('a throwing submit handler still gives the field back', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var calls = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SizedBox(
            height: 200,
            child: CommandInput(
              focusNode: focus,
              style: const TextStyle(fontSize: 16),
              onSubmit: (command) async {
                calls++;
                if (calls == 1) throw StateError('boom');
                return CommandOutcome.rejected;
              },
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'rate dune 5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Editable again: typing changes the text.
    await tester.enterText(find.byType(TextField), 'rate dune 4');
    expect(find.text('rate dune 4'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'rate dune 5');
    // And it accepts the next submission.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 500));
    expect(calls, 2);
  });

  // The keyboard stays up through a submit, so the next command can be typed
  // straight away — the field keeps focus the whole time, and refuses edits
  // (rather than going read-only, which drops the keyboard) while it runs.
  testWidgets('keeps focus through a submit, and refuses typing while busy', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final outcome = Completer<CommandOutcome>();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SizedBox(
            height: 200,
            child: CommandInput(
              focusNode: focus,
              style: const TextStyle(fontSize: 16),
              onSubmit: (_) => outcome.future,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'start dune');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    // While the command runs, the text is exactly what was submitted.
    tester.testTextInput.enterText('start dune messiah');
    await tester.pump();
    expect(find.text('start dune'), findsOneWidget);

    outcome.complete(CommandOutcome.accepted);
    await tester.pump();
    // The strike-through animation, then the hold before the field clears.
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();

    expect(find.text('start dune'), findsNothing);
    expect(focus.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });
}
