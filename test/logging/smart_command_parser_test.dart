import 'package:book/features/logging/domain/smart_command_parser.dart';
import 'package:flutter_test/flutter_test.dart';

const _dune = SmartBook(title: 'Dune', author: 'Frank Herbert');
const _messiah = SmartBook(title: 'Dune Messiah', author: 'Frank Herbert');
const _pride = SmartBook(title: 'Pride and Prejudice', author: 'Jane Austen');
const _goblet = SmartBook(
  title: 'Harry Potter and the Goblet of Fire',
  author: 'J.K. Rowling',
);
const _prisoner = SmartBook(
  title: 'Harry Potter and the Prisoner of Azkaban',
  author: 'J.K. Rowling',
);

// A Wednesday.
final _today = DateTime(2026, 9, 16);

List<SmartLine> _parse(String message, [List<SmartBook>? library]) =>
    SmartCommandParser.parse(
      message,
      library: library ?? const [_dune, _messiah, _pride],
      today: _today,
    );

List<String> _commands(String message, [List<SmartBook>? library]) => [
  for (final line in _parse(message, library))
    switch (line) {
      ResolvedLine(:final command) => command,
      NeedsBookLine(:final query) => 'ASK($query)',
      UnrecognizedLine(:final text) => 'UNKNOWN($text)',
    },
];

void main() {
  group('commands pass through', () {
    test('an exact command runs as typed', () {
      expect(_commands('finish Dune'), ['finish Dune']);
      expect(_commands('update Dune 50'), ['update Dune 50']);
    });

    test('a typo in a command title is fixed against the shelf', () {
      expect(_commands('finish dnue'), ['finish Dune']);
      expect(_commands('rate dune mesiah 4'), ['rate Dune Messiah 4']);
    });

    test('non-book commands are untouched', () {
      expect(_commands('make tag sci-fi'), ['make tag sci-fi']);
    });
  });

  group('sentences', () {
    test('start', () {
      expect(_commands("I've started reading Dune"), ['start Dune']);
      expect(_commands('began pride and prejudice'), [
        'start Pride and Prejudice',
      ]);
    });

    test('progress by page, percent and fraction', () {
      expect(_commands("I'm on page 120 of Dune"), ['update Dune 120']);
      expect(_commands('dune messiah 40% done'), ['update Dune Messiah 40%']);
      expect(_commands('halfway through dune'), ['update Dune 50%']);
    });

    test('finish, with a date', () {
      expect(_commands('finished dune yesterday'), ['finish Dune 2026-09-15']);
      expect(_commands('done with Dune last night'), [
        'finish Dune 2026-09-15',
      ]);
      expect(_commands('finished dune 3 days ago'), ['finish Dune 2026-09-13']);
      expect(_commands('finished dune on monday'), ['finish Dune 2026-09-14']);
    });

    test('ratings, including words and halves', () {
      expect(_commands('gave dune 4 stars'), ['rate Dune 4']);
      expect(_commands('dune: four and a half stars'), ['rate Dune 4.5']);
      expect(_commands('rated dune messiah 3/5'), ['rate Dune Messiah 3']);
    });

    test('did not finish, to read, re-read and delete', () {
      expect(_commands('gave up on dune messiah'), ['move Dune Messiah "dnf"']);
      expect(_commands('I want to read The Hobbit'), ['move hobbit "tbr"']);
      expect(_commands('re-reading dune'), ['restart Dune']);
      expect(_commands('get rid of dune messiah'), ['delete Dune Messiah']);
    });

    test('the author is ignored when matching', () {
      expect(_commands('finished dune by frank herbert'), ['finish Dune']);
    });

    test('a book not on the shelf passes through for Google Books', () {
      expect(_commands('started the martian'), ['start martian']);
    });
  });

  group('several actions in one message', () {
    test('split on and, then, commas and full stops', () {
      expect(_commands('finished dune yesterday and gave it 5 stars'), [
        'finish Dune 2026-09-15',
        'rate Dune 5',
      ]);
      expect(
        _commands('Finished Dune. Started Dune Messiah, on page 10 of it'),
        ['finish Dune', 'start Dune Messiah', 'update Dune Messiah 10'],
      );
    });

    test('"and" inside a title is not a split', () {
      expect(_commands('started pride and prejudice then finished dune'), [
        'start Pride and Prejudice',
        'finish Dune',
      ]);
    });
  });

  group('asking which book', () {
    test('no book named, nothing being read, asks', () {
      final lines = _parse('finished it yesterday');
      expect(lines.single, isA<NeedsBookLine>());
      final ask = lines.single as NeedsBookLine;
      expect(ask.query, '');
      expect(ask.commandFor('Dune'), 'finish Dune 2026-09-15');
    });

    test('no book named uses the book being read', () {
      expect(
        _commands('finished it', const [
          SmartBook(title: 'Dune', author: 'Frank Herbert', isReading: true),
        ]),
        ['finish Dune'],
      );
    });

    test('an ambiguous title asks, with the words typed', () {
      final lines = _parse('finish harry potter', const [_goblet, _prisoner]);
      final ask = lines.single as NeedsBookLine;
      expect(ask.query, 'harry potter');
      expect(
        ask.commandFor(_prisoner.title),
        'finish Harry Potter and the Prisoner of Azkaban',
      );
    });

    test('an ambiguous title prefers the book being read', () {
      const reading = SmartBook(
        title: 'Harry Potter and the Prisoner of Azkaban',
        author: 'J.K. Rowling',
        isReading: true,
      );
      expect(_commands('finished harry potter', const [_goblet, reading]), [
        'finish Harry Potter and the Prisoner of Azkaban',
      ]);
    });

    test('a clearly better match does not ask', () {
      expect(_commands('finished dune'), ['finish Dune']);
    });
  });

  test('gibberish is left for the parser to refuse', () {
    expect(_commands('the weather is nice'), ['UNKNOWN(the weather is nice)']);
  });
}
