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

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.readOnly, isFalse);
    expect(find.text('rate dune 5'), findsOneWidget);

    // And it accepts the next submission.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 500));
    expect(calls, 2);
  });
}
