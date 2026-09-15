import 'package:book/core/formatting/numbers.dart';
import 'package:book/features/logging/domain/log_command_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatCompactNumber', () {
    test('drops a trailing .0 and keeps at most one decimal', () {
      expect(formatCompactNumber(5), '5');
      expect(formatCompactNumber(4.5), '4.5');
      expect(formatCompactNumber(74.96), '75');
      expect(formatCompactNumber(0.5), '0.5');
    });

    test('writes non-finite values as symbols instead of throwing', () {
      expect(formatCompactNumber(double.infinity), '∞');
      expect(formatCompactNumber(double.negativeInfinity), '-∞');
      expect(formatCompactNumber(double.nan), '?');
      expect(formatCompactNumber(1e300), isNotEmpty);
    });
  });

  group('roundToHalf', () {
    test('rounds to the nearest half', () {
      expect(roundToHalf(4.3), 4.5);
      expect(roundToHalf(4.2), 4);
    });

    test('passes a value it cannot round back unchanged', () {
      expect(roundToHalf(double.infinity), double.infinity);
      expect(roundToHalf(double.nan).isNaN, isTrue);
      expect(roundToHalf(double.maxFinite), double.maxFinite);
    });
  });

  // Regression: a long enough run of digits parses to infinity, and the
  // parser's own formatting used to throw on it — which, before the add
  // tab caught unexpected errors, left the command field read-only.
  group('LogCommandParser with runaway numbers', () {
    final digits = '9' * 400;

    test('rate', () {
      final parsed = LogCommandParser.parse('rate Dune $digits');
      expect(parsed.recognized, isTrue);
      expect(parsed.rating, double.infinity);
    });

    test('update by percent', () {
      final parsed = LogCommandParser.parse('update Dune $digits%');
      expect(parsed.recognized, isTrue);
      expect(parsed.percent, double.infinity);
    });
  });
}
