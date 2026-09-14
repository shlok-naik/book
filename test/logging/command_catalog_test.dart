import 'package:book/features/logging/domain/command_catalog.dart';
import 'package:book/features/logging/domain/log_command_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// The catalog is the help text for the settings commands page and the
/// parser's suggestions — these tests keep it honest against the grammar
/// it describes.
void main() {
  test('every example in the catalog is a command the parser recognizes', () {
    for (final command in CommandCatalog.all) {
      final parsed = LogCommandParser.parse(command.example);
      expect(
        parsed.recognized,
        isTrue,
        reason: '"${command.example}" should parse (${command.keyword})',
      );
      expect(
        parsed.type.name.toLowerCase(),
        command.keyword.replaceAll(' ', ''),
        reason: '"${command.example}" should parse as ${command.keyword}',
      );
    }
  });

  test('lists the make-first command set, and none of the removed ones', () {
    final syntaxes = CommandCatalog.all.map((c) => c.syntax).toList();
    expect(
      syntaxes,
      containsAll(const [
        'start <book> [date]',
        'start isbn [date]',
        'update <book> <page or percent%> [date]',
        'finish <book> [date]',
        'rate <book> <stars>',
        'delete <book>',
        'move <book> <shelf>',
        'make shelf <shelf name>',
        'make tag <tag>',
        'add tag <tag> <book>',
        'make series <series name>',
        'add series <series> [#n] <book>',
        'add comment <comment> <book>',
      ]),
    );
    final keywords = CommandCatalog.all.map((c) => c.keyword);
    expect(keywords, isNot(contains('add shelf')));
    expect(keywords, isNot(contains('series')));
    expect(keywords, isNot(contains('start series')));
  });

  test('free commands exclude the pro-only ones', () {
    expect(CommandCatalog.free.any((c) => c.proOnly), isFalse);
    expect(CommandCatalog.all.where((c) => c.proOnly).map((c) => c.keyword), [
      'remember',
      'recommend',
    ]);
  });

  test('every built-in shelf keyword parses as a move', () {
    for (final shelf in CommandCatalog.shelves) {
      final parsed = LogCommandParser.parse('move Dune $shelf');
      expect(parsed.type, LogCommandType.move);
      expect(parsed.argument, 'Dune $shelf');
    }
  });
}
