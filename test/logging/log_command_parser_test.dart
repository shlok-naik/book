import 'package:book/features/logging/domain/log_command_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('start isbn', () {
    test('is recognized, with no title yet — the scan resolves one', () {
      final parsed = LogCommandParser.parse('start isbn');

      expect(parsed.recognized, isTrue);
      expect(parsed.type, LogCommandType.startIsbn);
      expect(parsed.title, isNull);
      expect(parsed.date, isNull);
    });

    test('carries a trailing date the same way start <book> does', () {
      final parsed = LogCommandParser.parse('start isbn 2026-08-31');

      expect(parsed.type, LogCommandType.startIsbn);
      expect(parsed.date, DateTime(2026, 8, 31));
    });

    test('a book literally titled "isbn" still starts by title', () {
      // Extremely unlikely in practice, but the pattern is checked first,
      // so this documents which way the ambiguity resolves.
      final parsed = LogCommandParser.parse('start isbn deluxe edition');

      expect(parsed.type, LogCommandType.start);
      expect(parsed.title, 'isbn deluxe edition');
    });
  });
}
