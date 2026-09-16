import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/logging/presentation/widgets/confirmation_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget pill) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: pill),
  ),
);

void main() {
  testWidgets('the words are exactly the message, title set in its own face', (
    tester,
  ) async {
    await _pump(
      tester,
      const ConfirmationPill(
        message: 'Started "Dune"',
        tone: ConfirmationTone.success,
      ),
    );

    expect(find.text('Started "Dune"'), findsOneWidget);
    final rich =
        tester.widget<Text>(find.text('Started "Dune"')).textSpan! as TextSpan;
    final title = rich.children!.whereType<TextSpan>().last;
    expect(title.text, '"Dune"');
    expect(title.style?.fontFamily, isNot(rich.style?.fontFamily));
  });

  testWidgets('the mark says how it went by shape, not colour alone', (
    tester,
  ) async {
    await _pump(
      tester,
      const ConfirmationPill(
        message: 'Finished "Dune"',
        tone: ConfirmationTone.success,
      ),
    );
    expect(find.byIcon(Icons.check), findsOneWidget);

    await _pump(
      tester,
      const ConfirmationPill(
        message: 'Rate 0.5–5 stars.',
        tone: ConfirmationTone.failure,
      ),
    );
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);

    await _pump(tester, const ConfirmationPill(message: 'Kept "Dune"'));
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('no grey chip — only a floating note gets a paper slip', (
    tester,
  ) async {
    Iterable<BoxDecoration> slips() => tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(ConfirmationPill),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .where((decoration) => decoration.border != null);

    await _pump(tester, const ConfirmationPill(message: 'Started "Dune"'));
    expect(slips(), isEmpty);

    await _pump(
      tester,
      const ConfirmationPill(
        message: 'Moved "Dune" to reading',
        floating: true,
      ),
    );
    // The page's own paper, not the cool grey surface the old chip used.
    expect(slips().single.color, AppTheme.light.scaffoldBackgroundColor);
  });

  testWidgets('an empty message draws nothing at all', (tester) async {
    await _pump(tester, const ConfirmationPill(message: ''));
    expect(find.byType(Icon), findsNothing);
  });
}
