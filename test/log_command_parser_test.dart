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

    group('add shelf', () {
      for (final (shelf, message) in [
        ('tbr', 'Added "Dune" to read'),
        ('reading', 'Moved "Dune" to reading'),
        ('finished', 'Added "Dune" as finished'),
        ('dnf', 'Marked "Dune" as DNF'),
      ]) {
        test('add shelf $shelf <book> parses the shelf, book and message', () {
          final result = LogCommandParser.parse('add shelf $shelf Dune');
          expect(result.recognized, isTrue);
          expect(result.type, LogCommandType.addShelf);
          expect(result.title, 'Dune');
          expect(result.shelf, shelf);
          expect(result.message, message);
        });
      }

      test('everything after the shelf keyword is the title', () {
        final result = LogCommandParser.parse('add shelf tbr The Bell Jar');
        expect(result.title, 'The Bell Jar');
        final tricky = LogCommandParser.parse(
          'add shelf dnf Finished Business',
        );
        expect(tricky.shelf, 'dnf');
        expect(tricky.title, 'Finished Business');
      });

      test('is case-insensitive on the keywords', () {
        final result = LogCommandParser.parse('Add Shelf TBR Dune');
        expect(result.recognized, isTrue);
        expect(result.shelf, 'tbr');
      });

      test('an unknown shelf or a missing title is unrecognized', () {
        expect(
          LogCommandParser.parse('add shelf later Dune').recognized,
          isFalse,
        );
        expect(LogCommandParser.parse('add shelf tbr').recognized, isFalse);
      });

      test('the old "add <book> <shelf>" syntax is no longer recognized', () {
        final result = LogCommandParser.parse('add Dune tbr');
        expect(result.recognized, isFalse);
        expect(
          result.message,
          contains('add shelf <tbr|reading|finished|dnf>'),
        );
      });

      test('suggests add shelf for a typo of add', () {
        final result = LogCommandParser.parse('ad shelf tbr Dune');
        expect(result.recognized, isFalse);
        expect(result.message, contains('add shelf'));
      });
    });

    group('add tag', () {
      test('parses a one-word tag and the book', () {
        final result = LogCommandParser.parse('add tag sci-fi Dune Messiah');
        expect(result.recognized, isTrue);
        expect(result.type, LogCommandType.addTag);
        expect(result.tag, 'sci-fi');
        expect(result.title, 'Dune Messiah');
        expect(result.message, 'Tagged "Dune Messiah" sci-fi');
      });

      test('a quoted tag can contain spaces, straight or curly quotes', () {
        final straight = LogCommandParser.parse('add tag "space opera" Dune');
        expect(straight.tag, 'space opera');
        expect(straight.title, 'Dune');
        final curly = LogCommandParser.parse('add tag “book club” Circe');
        expect(curly.tag, 'book club');
        expect(curly.title, 'Circe');
      });

      test('a tag with no book, or an empty quoted tag, is unrecognized', () {
        expect(LogCommandParser.parse('add tag sci-fi').recognized, isFalse);
        expect(LogCommandParser.parse('add tag "  " Dune').recognized, isFalse);
      });

      test('suggests add tag for a typo of tag', () {
        final result = LogCommandParser.parse('add tags sci-fi Dune');
        expect(result.recognized, isFalse);
        expect(result.message, contains('add tag <tag> <book>'));
      });
    });

    group('add comment', () {
      test('a quoted comment is split from the book here', () {
        final result = LogCommandParser.parse(
          'add comment "lost me in the middle" Dune',
        );
        expect(result.recognized, isTrue);
        expect(result.type, LogCommandType.addComment);
        expect(result.note, 'lost me in the middle');
        expect(result.title, 'Dune');
        expect(result.message, 'Commented on "Dune"');
      });

      test('an unquoted comment leaves the split to the library', () {
        final result = LogCommandParser.parse('add comment loved it Dune');
        expect(result.recognized, isTrue);
        expect(result.type, LogCommandType.addComment);
        expect(result.title, isNull);
        expect(result.note, 'loved it Dune');
      });

      test('a comment keeps apostrophes and inner punctuation', () {
        final result = LogCommandParser.parse(
          "add comment \"didn't click: too slow\" Ulysses",
        );
        expect(result.note, "didn't click: too slow");
        expect(result.title, 'Ulysses');
      });

      test('a single word after add comment is unrecognized', () {
        expect(LogCommandParser.parse('add comment Dune').recognized, isFalse);
        expect(
          LogCommandParser.parse('add comment "" Dune').recognized,
          isFalse,
        );
      });
    });

    test('update <book> <percent>% parses the book, percent, and '
        'confirmation', () {
      final result = LogCommandParser.parse('update The Shining 74%');
      expect(result.recognized, isTrue);
      expect(result.type, LogCommandType.update);
      expect(result.title, 'The Shining');
      expect(result.percent, 74);
      expect(result.page, isNull);
      expect(result.message, '"The Shining" — 74%');
    });

    test('update percent keeps a real fraction but drops a trailing '
        '".0"', () {
      final wholeNumber = LogCommandParser.parse('update Dune 50%');
      expect(wholeNumber.message, '"Dune" — 50%');

      final fraction = LogCommandParser.parse('update Dune 50.5%');
      expect(fraction.percent, 50.5);
      expect(fraction.message, '"Dune" — 50.5%');
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
      expect(result.message, contains('update <book> <page or percent%>'));
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

  group('series', () {
    test('series <name> #n <book>', () {
      final result = LogCommandParser.parse('series dune #2 Dune Messiah');
      expect(result.recognized, isTrue);
      expect(result.type, LogCommandType.series);
      expect(result.series, 'dune');
      expect(result.seriesPosition, 2);
      expect(result.title, 'Dune Messiah');
      expect(result.message, 'Filed "Dune Messiah" under dune #2');
    });

    test('a quoted multi-word series, no number', () {
      final result = LogCommandParser.parse(
        'series "the expanse" Leviathan Wakes',
      );
      expect(result.type, LogCommandType.series);
      expect(result.series, 'the expanse');
      expect(result.seriesPosition, isNull);
      expect(result.title, 'Leviathan Wakes');
    });

    test('a half-numbered novella', () {
      final result = LogCommandParser.parse('series dune #1.5 Dune: A Novella');
      expect(result.seriesPosition, 1.5);
      expect(result.message, 'Filed "Dune: A Novella" under dune #1.5');
    });

    test('series without a book is not recognized', () {
      final result = LogCommandParser.parse('series dune');
      expect(result.recognized, isFalse);
      expect(result.message, contains('series <series> [#n] <book>'));
    });

    test('start series takes the rest of the line as the series', () {
      final result = LogCommandParser.parse('start series the expanse');
      expect(result.recognized, isTrue);
      expect(result.type, LogCommandType.startSeries);
      expect(result.series, 'the expanse');
      expect(result.title, isNull);
    });

    test('start series with a quoted name', () {
      final result = LogCommandParser.parse('start series "Dune"');
      expect(result.type, LogCommandType.startSeries);
      expect(result.series, 'Dune');
    });

    test('plain start is unaffected', () {
      final result = LogCommandParser.parse('start Seriously Funny');
      expect(result.type, LogCommandType.start);
      expect(result.title, 'Seriously Funny');
    });
  });
}
