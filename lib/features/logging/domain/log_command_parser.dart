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

  static const _firstWordPattern = r'^(\S+)';
  static const _keywords = ['start', 'update', 'finish', 'rate'];
  static const _usage = {
    'start': 'start <book>',
    'update': 'update <book> <page>',
    'finish': 'finish <book>',
    'rate': 'rate <book> <star value> stars',
  };

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

    return ParsedLogCommand(message: _suggestionFor(text), recognized: false);
  }

  /// Finds the closest known keyword to the input's first word (by edit
  /// distance) and suggests its usage — falls back to a generic hint.
  static String _suggestionFor(String text) {
    final firstWord = RegExp(_firstWordPattern).firstMatch(text)?.group(1);
    if (firstWord != null) {
      final closest = _closestKeyword(firstWord.toLowerCase());
      if (closest != null) {
        return 'Not recognized. Did you mean "${_usage[closest]}"?';
      }
    }
    return 'Not recognized. Try "start Dune", "update Dune 120", '
        '"finish Dune", or "rate Dune 5 stars".';
  }

  /// A word only needs to be "close enough" relative to its own length —
  /// a fixed edit-distance cap was too strict for longer typos/variants
  /// like "finsiher" for "finish".
  static const _similarityThreshold = 0.5;

  static String? _closestKeyword(String word) {
    String? best;
    var bestSimilarity = 0.0;
    for (final keyword in _keywords) {
      final distance = _levenshtein(word, keyword);
      final maxLength = word.length > keyword.length ? word.length : keyword.length;
      final similarity = maxLength == 0 ? 0.0 : 1 - (distance / maxLength);
      if (similarity > bestSimilarity) {
        bestSimilarity = similarity;
        best = keyword;
      }
    }
    return (best != null && bestSimilarity >= _similarityThreshold) ? best : null;
  }

  static int _levenshtein(String a, String b) {
    final rows = a.length + 1;
    final cols = b.length + 1;
    final dp = List.generate(rows, (_) => List<int>.filled(cols, 0));
    for (var i = 0; i < rows; i++) {
      dp[i][0] = i;
    }
    for (var j = 0; j < cols; j++) {
      dp[0][j] = j;
    }
    for (var i = 1; i < rows; i++) {
      for (var j = 1; j < cols; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        final deletion = dp[i - 1][j] + 1;
        final insertion = dp[i][j - 1] + 1;
        final substitution = dp[i - 1][j - 1] + cost;
        dp[i][j] = [deletion, insertion, substitution].reduce((x, y) => x < y ? x : y);
      }
    }
    return dp[rows - 1][cols - 1];
  }
}
