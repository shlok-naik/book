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

  /// The command's first word(s) — `start`, `add shelf`, `remember` — and
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
  /// The shelf keywords `add shelf` accepts, in shelf order.
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
          'journal history. asks you to confirm first.',
      example: 'delete Dune',
    ),
    CommandReference(
      keyword: 'add shelf',
      syntax: 'add shelf <tbr|reading|finished|dnf> <book>',
      description:
          'adds a book straight to a shelf, or moves one that is already '
          'on another. to read and reading start it at page 0; finished '
          'sets it to 100%; dnf keeps how far you got.',
      example: 'add shelf tbr Piranesi',
    ),
    CommandReference(
      keyword: 'add tag',
      syntax: 'add tag <tag> <book>',
      description:
          'labels a book on your shelf. one word, or wrap a longer tag in '
          'quotes: add tag "space opera" Dune.',
      example: 'add tag sci-fi Dune',
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
      keyword: 'series',
      syntax: 'series <series> [#n] <book>',
      description:
          'files a book on your shelf under a series, optionally with its '
          'number. one word, or quote a longer name: series "the expanse" '
          '#1 leviathan wakes. series are shared, so the first reader to '
          'file a book decides where it goes.',
      example: 'series dune #2 Dune Messiah',
    ),
    CommandReference(
      keyword: 'start series',
      syntax: 'start series <series>',
      description:
          'starts the next book in a series — the first one you have not '
          'finished or dropped.',
      example: 'start series dune',
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
