import 'package:book/core/theme/app_theme.dart';
import 'package:book/core/widgets/date_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpPill(WidgetTester tester, DateTime? date) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: DatePill(date: date)),
      ),
    );
  }

  testWidgets('labels today, yesterday, and tomorrow as words', (
    WidgetTester tester,
  ) async {
    final now = DateTime.now();

    await pumpPill(tester, now);
    expect(find.text('today'), findsOneWidget);

    await pumpPill(tester, now.subtract(const Duration(days: 1)));
    expect(find.text('yesterday'), findsOneWidget);

    await pumpPill(tester, now.add(const Duration(days: 1)));
    expect(find.text('tomorrow'), findsOneWidget);
  });

  testWidgets('falls back to weekday, dd.mm for any other day', (
    WidgetTester tester,
  ) async {
    await pumpPill(tester, DateTime(2026, 3, 5));
    expect(find.text('thu, 05.03'), findsOneWidget);
  });
}
