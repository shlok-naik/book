import 'package:book/core/theme/text_size_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(TextSizeController.reset);

  Future<double> scaleOf(
    WidgetTester tester, {
    double system = 1,
    required TextSize size,
  }) async {
    TextSizeController.size.value = size;
    late double scaled;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(system)),
        child: ReaderTextScale(
          child: Builder(
            builder: (context) {
              scaled = MediaQuery.textScalerOf(context).scale(10);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return scaled;
  }

  testWidgets('standard leaves the system size alone', (tester) async {
    expect(await scaleOf(tester, system: 1.2, size: TextSize.standard), 12);
  });

  testWidgets('larger sizes multiply the system size', (tester) async {
    expect(await scaleOf(tester, size: TextSize.largest), closeTo(13, 0.001));
    expect(
      await scaleOf(tester, system: 1.5, size: TextSize.large),
      closeTo(17.25, 0.001),
    );
  });

  testWidgets('capped, but never below the system size', (tester) async {
    expect(
      await scaleOf(tester, system: 2, size: TextSize.largest),
      closeTo(24, 0.001),
    );
    expect(
      await scaleOf(tester, system: 3, size: TextSize.largest),
      closeTo(30, 0.001),
    );
  });
}
