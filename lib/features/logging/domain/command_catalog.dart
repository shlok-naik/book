/// One text command, as a reader would look it up: its syntax, what it
/// does, and a line they could type.
class CommandReference {
  const CommandReference({
    required this.keyword,
    required this.syntax,
    required this.description,
    required this.example,
    this.proOnly = false,
  });

  /// The command's first word(s) — `start`, `make tag`, `remember` — and
  /// the key `LogCommandParser` suggests usage by.
  final String keyword;

  /// The canonical form, with `<placeholders>` and `[optional]` parts.
  final String syntax;

  final String description;
  final String example;

  /// Only ever produced by cactus pro's natural-language mode, never typed.
  final bool proOnly;
}

/// Every text command the add tab understands, in the order a reader meets
/// them. The single source for the settings "commands" page, the parser's
/// "did you mean" suggestions, and (for the syntax lines) onboarding — so a
/// command added to the grammar can't be missing from the help that
/// describes it. `test/logging/command_catalog_test.dart` parses every
/// [CommandReference.example] to prove each one is real.
abstract final class CommandCatalog {
  /// The built-in shelf keywords `move` accepts, in shelf order. (It also
  /// accepts the longer "to read" and "did not finish", and any shelf the
  /// reader made — see `CollectionNames.builtInShelves`.)
  static const shelves = ['tbr', 'reading', 'finished', 'dnf'];

  static const all = <CommandReference>[
    CommandReference(
      keyword: 'start',
      syntax: 'start <book> [date]',
      description:
          'puts a book on your reading shelf at page 0. add a date '
          '(YYYY-MM-DD) to log it for another day.',
      example: 'start Dune',
    ),
    CommandReference(
      keyword: 'start isbn',
      syntax: 'start isbn [date]',
      description:
          'opens your camera to scan a book\'s barcode, then starts '
          'whatever it finds — for when typing the title is more trouble '
          'than pointing your phone at it.',
      example: 'start isbn',
    ),
    CommandReference(
      keyword: 'update',
      syntax: 'update <book> <page or percent%> [date]',
      description:
          'logs how far you have read, as a page number or a percentage. '
          'reaching the last page finishes the book.',
      example: 'update Dune 120',
    ),
    CommandReference(
      keyword: 'finish',
      syntax: 'finish <book> [date]',
      description: 'marks a book finished and fills its progress to 100%.',
      example: 'finish Dune',
    ),
    CommandReference(
      keyword: 'restart',
      syntax: 'restart <book> [date]',
      description:
          'puts a finished book back on your reading shelf for another '
          'read, at page 0.',
      example: 'restart Dune',
    ),
    CommandReference(
      keyword: 'rate',
      syntax: 'rate <book> <stars>',
      description: 'rates a finished book from 0.5 to 5 stars, in halves.',
      example: 'rate Dune 4.5',
    ),
    CommandReference(
      keyword: 'delete',
      syntax: 'delete <book>',
      description:
          'removes a book from your library, with its tags, comments and '
          'reading history. asks you to confirm first.',
      example: 'delete Dune',
    ),
    CommandReference(
      keyword: 'move',
      syntax: 'move <book> <shelf>',
      description:
          'puts a book on a shelf: tbr, reading, finished, dnf, or one you '
          'made. to read and reading start it at page 0; finished sets it '
          'to 100%; dnf and your own shelves keep how far you got. quote a '
          'shelf name with spaces if the title is ambiguous: '
          'move Dune "summer reads".',
      example: 'move Piranesi tbr',
    ),
    CommandReference(
      keyword: 'make shelf',
      syntax: 'make shelf <shelf name>',
      description:
          'makes a shelf of your own, shown under the built-in ones in your '
          'library. then move books onto it.',
      example: 'make shelf summer reads',
    ),
    CommandReference(
      keyword: 'make tag',
      syntax: 'make tag <tag>',
      description:
          'makes a tag you can put on books. make it once, then add it to '
          'as many books as you like.',
      example: 'make tag sci-fi',
    ),
    CommandReference(
      keyword: 'add tag',
      syntax: 'add tag <tag> <book>',
      description:
          'puts a tag you made on a book on your shelf. one word, or wrap a '
          'longer tag in quotes: add tag "space opera" Dune.',
      example: 'add tag sci-fi Dune',
    ),
    CommandReference(
      keyword: 'make series',
      syntax: 'make series <series name>',
      description:
          'makes a series, or adds one another reader already made to your '
          'list. then file books under it.',
      example: 'make series dune',
    ),
    CommandReference(
      keyword: 'add series',
      syntax: 'add series <series> [#n] <book>',
      description:
          'files a book on your shelf under a series you made, optionally '
          'with its number. one word, or quote a longer name: add series '
          '"the expanse" #1 leviathan wakes. series are shared, so the first '
          'reader to file a book decides where it goes.',
      example: 'add series dune #2 Dune Messiah',
    ),
    CommandReference(
      keyword: 'add comment',
      syntax: 'add comment <comment> <book>',
      description:
          'writes a note on a book on your shelf — like why you stopped '
          'reading a dnf. quotes around the comment are optional.',
      example: 'add comment "lost me in the middle" Dune',
    ),
    CommandReference(
      keyword: 'remove shelf',
      syntax: 'remove shelf <shelf> [book]',
      description:
          'with a book, takes it off a shelf you made and back to its own '
          'shelf, progress kept. with no book, removes the shelf itself '
          '(after asking) — its books go back to their own shelves. quote a '
          'name with spaces if it runs into the title.',
      example: 'remove shelf summer Piranesi',
    ),
    CommandReference(
      keyword: 'remove tag',
      syntax: 'remove tag <tag> [book]',
      description:
          'with a book, takes a tag off it. with no book, removes the tag '
          'itself, from every book it was on (after asking).',
      example: 'remove tag sci-fi Dune',
    ),
    CommandReference(
      keyword: 'remove series',
      syntax: 'remove series <series> [book]',
      description:
          'with a book, takes it out of a series, number and all. with no '
          'book, removes the series itself (after asking).',
      example: 'remove series dune Dune Messiah',
    ),
    CommandReference(
      keyword: 'remove comment',
      syntax: 'remove comment [comment] <book>',
      description:
          'removes a comment from a book, after showing you which. name the '
          'comment (or how it starts) to pick one; leave it out for the '
          'latest: remove comment Dune.',
      example: 'remove comment "lost me in the middle" Dune',
    ),
    CommandReference(
      keyword: 'remember',
      syntax: 'remember <book> :: <note>',
      description:
          'saves how a book made you feel to your memory tab. written for '
          'you by cactus pro when you describe your reading.',
      example: 'remember Dune :: loved the desert politics',
      proOnly: true,
    ),
    CommandReference(
      keyword: 'recommend',
      syntax: 'recommend <book> :: <reason>',
      description:
          'suggests your next read from your shelf and memories. cactus pro '
          'writes it when you ask for a recommendation.',
      example: 'recommend Hyperion :: more epic sci-fi like Dune',
      proOnly: true,
    ),
  ];

  /// Commands a reader can type on the free plan.
  static List<CommandReference> get free =>
      all.where((command) => !command.proOnly).toList(growable: false);

  static CommandReference? byKeyword(String keyword) {
    for (final command in all) {
      if (command.keyword == keyword) return command;
    }
    return null;
  }
}
