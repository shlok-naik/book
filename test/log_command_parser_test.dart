import 'package:book/features/logging/domain/log_command_parser.dart';
import 'package:flutter_test/flutter_test.dart';

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

    test('remember parses the book, note, and confirmation', () {
      final result = LogCommandParser.parse(
        'remember Dune :: loved the ending',
      );
      expect(result.recognized, isTrue);
      expect(result.type, LogCommandType.remember);
      expect(result.title, 'Dune');
      expect(result.note, 'loved the ending');
      expect(result.message, 'Remembered "Dune" — loved the ending');
    });

    test('remember requires the "::" separator, not just a space', () {
      expect(
        LogCommandParser.parse('remember Dune loved the ending').recognized,
        isFalse,
      );
    });

    test('recommend parses the recommended title, reason, and pill', () {
      final result = LogCommandParser.parse(
        'recommend Circe :: another morally complex retelling',
      );
      expect(result.recognized, isTrue);
      expect(result.type, LogCommandType.recommend);
      expect(result.title, 'Circe');
      expect(result.note, 'another morally complex retelling');
      expect(result.message, '"Circe" — another morally complex retelling');
    });

    test(
      'a typo of "remember"/"recommend" never suggests the pro-only syntax',
      () {
        // Free-plan readers can type these two keywords by mistake, but
        // never in the exact `remember Dune :: ...` shape an AI would —
        // the fuzzy-match suggestion must stay silent about them rather
        // than teach a pro-only command to someone typing manually.
        final remember = LogCommandParser.parse('remeber Dune');
        expect(remember.recognized, isFalse);
        expect(remember.message, isNot(contains('remember')));

        final recommend = LogCommandParser.parse('recomend fantasy');
        expect(recommend.recognized, isFalse);
        expect(recommend.message, isNot(contains('recommend')));
      },
    );

    group('optional trailing date', () {
      test('start with no date behaves exactly as before', () {
        final result = LogCommandParser.parse('start Dune');
        expect(result.type, LogCommandType.start);
        expect(result.title, 'Dune');
        expect(result.date, isNull);
        expect(result.message, 'Started "Dune"');
      });

      test('start with a date backdates the title and the pill', () {
        final result = LogCommandParser.parse('start Dune 2026-08-31');
        expect(result.recognized, isTrue);
        expect(result.type, LogCommandType.start);
        expect(result.title, 'Dune');
        expect(result.date, DateTime(2026, 8, 31));
        expect(result.message, 'Started "Dune" — Aug 31');
      });

      test('update takes a date after the page number, not before', () {
        final result = LogCommandParser.parse('update Dune 120 2026-08-31');
        expect(result.recognized, isTrue);
        expect(result.type, LogCommandType.update);
        expect(result.title, 'Dune');
        expect(result.page, 120);
        expect(result.date, DateTime(2026, 8, 31));
        expect(result.message, '"Dune" — pg 120 — Aug 31');
      });

      test('finish with a date', () {
        final result = LogCommandParser.parse('finish Dune 2026-08-31');
        expect(result.type, LogCommandType.finish);
        expect(result.title, 'Dune');
        expect(result.date, DateTime(2026, 8, 31));
        expect(result.message, 'Finished "Dune" — Aug 31');
      });

      test(
        'a title that merely contains digits is not mistaken for a date',
        () {
          final result = LogCommandParser.parse('start 1984');
          expect(result.recognized, isTrue);
          expect(result.title, '1984');
          expect(result.date, isNull);
        },
      );
    });
  });
}
