import 'package:flutter_test/flutter_test.dart';

import 'package:book/features/logging/domain/log_command_parser.dart';

void main() {
  group('LogCommandParser', () {
    test('recognizes all five commands', () {
      expect(LogCommandParser.parse('start Dune').recognized, isTrue);
      expect(LogCommandParser.parse('update Dune 120').recognized, isTrue);
      expect(LogCommandParser.parse('finish Dune').recognized, isTrue);
      expect(LogCommandParser.parse('rate Dune 5').recognized, isTrue);
      expect(LogCommandParser.parse('delete Dune').recognized, isTrue);
    });

    test('delete parses the book and confirms removal', () {
      final result = LogCommandParser.parse('delete Dune');
      expect(result.type, LogCommandType.delete);
      expect(result.title, 'Dune');
      expect(result.message, 'Removed "Dune"');
    });

    test('rate takes just a number, no trailing "stars"', () {
      final result = LogCommandParser.parse('rate Dune 5');
      expect(result.type, LogCommandType.rate);
      expect(result.title, 'Dune');
      expect(result.rating, 5);
      expect(result.message, '"Dune" — 5★');
      // The old "rate Dune 5 stars" form is no longer accepted.
      expect(LogCommandParser.parse('rate Dune 5 stars').recognized, isFalse);
    });

    test('rounds a rating to the nearest half star', () {
      final closerToHalf = LogCommandParser.parse('rate Dune 4.3');
      expect(closerToHalf.rating, 4.5);
      expect(closerToHalf.message, '"Dune" — 4.5★');

      final closerToWhole = LogCommandParser.parse('rate Dune 4.2');
      expect(closerToWhole.rating, 4.0);
      expect(closerToWhole.message, '"Dune" — 4★');
    });

    test('suggests the closest keyword for a small typo', () {
      final result = LogCommandParser.parse('strat Dune');
      expect(result.recognized, isFalse);
      expect(result.message, contains('start <book>'));
    });

    test('suggests "update" for a typo of it', () {
      final result = LogCommandParser.parse('updat Dune 50');
      expect(result.recognized, isFalse);
      expect(result.message, contains('update <book> <page>'));
    });

    test('suggests "finish" for a longer, messier typo', () {
      final result = LogCommandParser.parse('finsiher Dune');
      expect(result.recognized, isFalse);
      expect(result.message, contains('finish <book>'));
    });

    test('suggests "delete" for a typo of it', () {
      final result = LogCommandParser.parse('delet Dune');
      expect(result.recognized, isFalse);
      expect(result.message, contains('delete <book>'));
    });

    test('falls back to the generic hint when nothing is close', () {
      final result = LogCommandParser.parse('gibberish');
      expect(result.recognized, isFalse);
      expect(result.message, isNot(contains('Did you mean')));
      expect(result.message, contains('Not recognized'));
    });
  });
}
