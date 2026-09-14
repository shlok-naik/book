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

    group('update page or percent', () {
      test('a bare number is a page', () {
        final result = LogCommandParser.parse('update Dune 100');
        expect(result.page, 100);
        expect(result.percent, isNull);
        expect(result.message, '"Dune" — pg 100');
      });

      test('a number followed by % is a percentage', () {
        final result = LogCommandParser.parse('update Dune 100%');
        expect(result.page, isNull);
        expect(result.percent, 100);
        expect(result.message, '"Dune" — 100%');
        expect(LogCommandParser.parse('update Dune 74.5 %').percent, 74.5);
      });
    });

    group('move', () {
      test('a quoted shelf is split from the title here', () {
        final result = LogCommandParser.parse(
          'move Dune Messiah "summer reads"',
        );
        expect(result.recognized, isTrue);
        expect(result.type, LogCommandType.move);
        expect(result.title, 'Dune Messiah');
        expect(result.shelf, 'summer reads');
        expect(result.argument, isNull);
        expect(result.message, 'Moved "Dune Messiah" to summer reads');
        final curly = LogCommandParser.parse('move Circe “to read”');
        expect(curly.shelf, 'to read');
      });

      test('an unquoted move is handed to the library whole', () {
        final result = LogCommandParser.parse('Move The Bell Jar tbr');
        expect(result.recognized, isTrue);
        expect(result.type, LogCommandType.move);
        expect(result.title, isNull);
        expect(result.shelf, isNull);
        expect(result.argument, 'The Bell Jar tbr');
      });

      test('a move without both a book and a shelf is unrecognized', () {
        expect(LogCommandParser.parse('move Dune').recognized, isFalse);
        expect(LogCommandParser.parse('move Dune ""').recognized, isFalse);
        expect(
          LogCommandParser.parse('move Dune').message,
          contains('move <book> <shelf>'),
        );
      });

      test('the old add shelf syntax is gone', () {
        final result = LogCommandParser.parse('add shelf tbr Dune');
        expect(result.type, isNot(LogCommandType.move));
        expect(result.type, isNot(LogCommandType.makeShelf));
      });
    });

    group('make', () {
      test('make shelf takes the rest of the line, quoted or not', () {
        final plain = LogCommandParser.parse('make shelf  summer   reads ');
        expect(plain.recognized, isTrue);
        expect(plain.type, LogCommandType.makeShelf);
        expect(plain.shelf, 'summer reads');
        expect(plain.title, isNull);
        expect(plain.message, 'Made shelf "summer reads"');
        expect(
          LogCommandParser.parse('make shelf "Summer reads"').shelf,
          'Summer reads',
        );
      });

      test('make tag and make series never name a book', () {
        final tag = LogCommandParser.parse('make tag space opera');
        expect(tag.type, LogCommandType.makeTag);
        expect(tag.tag, 'space opera');
        expect(tag.title, isNull);

        final series = LogCommandParser.parse('Make Series “The Expanse”');
        expect(series.type, LogCommandType.makeSeries);
        expect(series.series, 'The Expanse');
        expect(series.title, isNull);
      });

      test('make with no name, or an unknown kind, is unrecognized', () {
        expect(LogCommandParser.parse('make tag').recognized, isFalse);
        expect(LogCommandParser.parse('make shelf ""').recognized, isFalse);
        final unknown = LogCommandParser.parse('make list favourites');
        expect(unknown.recognized, isFalse);
        expect(unknown.message, contains('make shelf <shelf name>'));
      });

      test('suggests the right make usage for a typo', () {
        expect(
          LogCommandParser.parse('mak serie dune').message,
          contains('make series <series name>'),
        );
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

  group('add series', () {
    test('add series <name> #n <book>', () {
      final result = LogCommandParser.parse('add series dune #2 Dune Messiah');
      expect(result.recognized, isTrue);
      expect(result.type, LogCommandType.addSeries);
      expect(result.series, 'dune');
      expect(result.seriesPosition, 2);
      expect(result.title, 'Dune Messiah');
      expect(result.message, 'Filed "Dune Messiah" under dune #2');
    });

    test('a quoted multi-word series, no number', () {
      final result = LogCommandParser.parse(
        'add series "the expanse" Leviathan Wakes',
      );
      expect(result.type, LogCommandType.addSeries);
      expect(result.series, 'the expanse');
      expect(result.seriesPosition, isNull);
      expect(result.title, 'Leviathan Wakes');
    });

    test('a half-numbered novella', () {
      final result = LogCommandParser.parse(
        'add series dune #1.5 Dune: A Novella',
      );
      expect(result.seriesPosition, 1.5);
      expect(result.message, 'Filed "Dune: A Novella" under dune #1.5');
    });

    test('add series without a book is not recognized', () {
      final result = LogCommandParser.parse('add series dune');
      expect(result.recognized, isFalse);
      expect(result.message, contains('add series <series> [#n] <book>'));
    });

    test('the old series and start series commands are gone', () {
      expect(
        LogCommandParser.parse('series dune #2 Dune Messiah').recognized,
        isFalse,
      );
      final startSeries = LogCommandParser.parse('start series dune');
      expect(
        startSeries.type,
        LogCommandType.start,
        reason: 'now just a book title, like any other start',
      );
      expect(startSeries.title, 'series dune');
    });
  });

  group('remove', () {
    test('remove tag <tag> <book>', () {
      final result = LogCommandParser.parse('remove tag sci-fi Dune Messiah');
      expect(result.recognized, isTrue);
      expect(result.type, LogCommandType.removeTag);
      expect(result.tag, 'sci-fi');
      expect(result.title, 'Dune Messiah');
      expect(result.message, 'Removed sci-fi from "Dune Messiah"');
    });

    test('a quoted tag can contain spaces', () {
      final result = LogCommandParser.parse('remove tag "space opera" Dune');
      expect(result.tag, 'space opera');
      expect(result.title, 'Dune');
    });

    test('remove shelf <shelf> <book>', () {
      final result = LogCommandParser.parse('remove shelf "summer reads" Dune');
      expect(result.recognized, isTrue);
      expect(result.type, LogCommandType.removeShelf);
      expect(result.shelf, 'summer reads');
      expect(result.title, 'Dune');
      expect(result.message, 'Removed "Dune" from summer reads');
    });

    test('remove series <series> <book>', () {
      final result = LogCommandParser.parse('remove series dune Dune Messiah');
      expect(result.recognized, isTrue);
      expect(result.type, LogCommandType.removeSeries);
      expect(result.series, 'dune');
      expect(result.title, 'Dune Messiah');
      expect(result.message, 'Removed "Dune Messiah" from dune');
    });

    test('a remove with no book is not recognized', () {
      expect(LogCommandParser.parse('remove tag sci-fi').recognized, isFalse);
      expect(LogCommandParser.parse('remove shelf tbr').recognized, isFalse);
      expect(LogCommandParser.parse('remove series dune').recognized, isFalse);
    });

    test('suggests remove tag for a typo of tag', () {
      final result = LogCommandParser.parse('remove tags sci-fi Dune');
      expect(result.recognized, isFalse);
      expect(result.message, contains('remove tag <tag> <book>'));
    });
  });
}
