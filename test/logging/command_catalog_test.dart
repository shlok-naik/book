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

  test('lists the new add family, and nothing in the old add syntax', () {
    final syntaxes = CommandCatalog.all.map((c) => c.syntax).toList();
    expect(syntaxes, contains('add shelf <tbr|reading|finished|dnf> <book>'));
    expect(syntaxes, contains('add tag <tag> <book>'));
    expect(syntaxes, contains('add comment <comment> <book>'));
    expect(syntaxes.where((s) => s.startsWith('add <book>')), isEmpty);
  });

  test('free commands exclude the pro-only ones', () {
    expect(CommandCatalog.free.any((c) => c.proOnly), isFalse);
    expect(CommandCatalog.all.where((c) => c.proOnly).map((c) => c.keyword), [
      'remember',
      'recommend',
    ]);
  });

  test('every shelf keyword is accepted by add shelf', () {
    for (final shelf in CommandCatalog.shelves) {
      expect(LogCommandParser.parse('add shelf $shelf Dune').shelf, shelf);
    }
  });
}
