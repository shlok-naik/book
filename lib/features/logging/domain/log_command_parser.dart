/// Zero-cost, rule-based parser for Structured mode commands:
/// `start <book>`, `update <book> <page>`, `finish <book>`,
/// `rate <book> <star value> stars`.
class ParsedLogCommand {
  const ParsedLogCommand({required this.message, required this.recognized});

  final String message;
  final bool recognized;
}

abstract final class LogCommandParser {
  static final _startPattern = RegExp(r'^start\s+(.+)$', caseSensitive: false);
  static final _updatePattern =
      RegExp(r'^update\s+(.+?)\s+(\d+)$', caseSensitive: false);
  static final _finishPattern = RegExp(r'^finish\s+(.+)$', caseSensitive: false);
  static final _ratePattern = RegExp(
    r'^rate\s+(.+?)\s+(\d+(?:\.\d+)?)\s*stars?$',
    caseSensitive: false,
  );

  static ParsedLogCommand parse(String input) {
    final text = input.trim();
    if (text.isEmpty) {
      return const ParsedLogCommand(message: '', recognized: false);
    }

    final rate = _ratePattern.firstMatch(text);
    if (rate != null) {
      final title = rate.group(1)!.trim();
      final rating = rate.group(2)!;
      return ParsedLogCommand(
        message: '"$title" — $rating★',
        recognized: true,
      );
    }

    final update = _updatePattern.firstMatch(text);
    if (update != null) {
      final title = update.group(1)!.trim();
      final page = update.group(2)!;
      return ParsedLogCommand(
        message: '"$title" — pg $page',
        recognized: true,
      );
    }

    final finish = _finishPattern.firstMatch(text);
    if (finish != null) {
      final title = finish.group(1)!.trim();
      return ParsedLogCommand(
        message: 'Finished "$title"',
        recognized: true,
      );
    }

    final start = _startPattern.firstMatch(text);
    if (start != null) {
      final title = start.group(1)!.trim();
      return ParsedLogCommand(
        message: 'Started "$title"',
        recognized: true,
      );
    }

    return const ParsedLogCommand(
      message: 'Not recognized. Try "start Dune", "update Dune 120", '
          '"finish Dune", or "rate Dune 5 stars".',
      recognized: false,
    );
  }
}
