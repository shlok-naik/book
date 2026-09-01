// Zero-cost, rule-based parser for Structured mode commands:
// `start <book> [date]`, `update <book> <page> [date]`,
// `finish <book> [date]`, `rate <book> <stars>`, `delete <book>` — the
// optional trailing date (`YYYY-MM-DD`) backdates the reading event it
// logs, so "I started Dune yesterday" (resolved to a concrete date by
// cactus pro before it ever reaches this parser) logs — and streaks —
// on that day rather than today. Plus two "cactus pro"-only commands
// that only ever arrive as an AI-extracted line, never typed directly:
// `remember <book> :: <note>` and `recommend <book> :: <reason>`.
// Recognizing their syntax here doesn't make them free-plan features —
// `HomePage` gates both behind `PlanController.isPro` at the point they'd
// actually run, the same way every other pro-only surface in the app is
// gated.
enum LogCommandType {
  start,
  update,
  finish,
  rate,
  delete,
  remember,
  recommend,
  unknown,
}

class ParsedLogCommand {
  const ParsedLogCommand({
    required this.message,
    required this.recognized,
    this.type = LogCommandType.unknown,
    this.title,
    this.page,
    this.rating,
    this.note,
    this.date,
  });

  /// Confirmation (or error/suggestion) text for the pill.
  final String message;
  final bool recognized;

  final LogCommandType type;

  /// The book the command refers to — null when unrecognized. For
  /// `recommend` this is the *recommended* title, not one already on
  /// the shelf.
  final String? title;

  /// Page argument of `update`. Always a non-negative int when present;
  /// the pattern only matches digits, so no sign or decimal can get in.
  final int? page;

  /// Star argument of `rate`.
  final double? rating;

  /// The free-text half of `remember` (the note itself) or `recommend`
  /// (why that book) — null for every other command.
  final String? note;

  /// The optional trailing `YYYY-MM-DD` on `start`/`update`/`finish` —
  /// "I started Dune yesterday" resolves to this, on cactus pro, before
  /// ever reaching this parser (see `parse-command`'s prompt). Null
  /// means "just now", same as before this existed. A plain calendar
  /// date with no time component — callers that persist it should
  /// treat it as local midnight on that day, not UTC.
  final DateTime? date;
}

abstract final class LogCommandParser {
  // Optional trailing `YYYY-MM-DD` on these three — lazy title capture
  // means it always tries the *shortest* title first, so "start Dune
  // 2026-08-31" splits into title "Dune" + date, rather than the date
  // getting swallowed into the title (same reasoning `_updatePattern`
  // already relies on for its own trailing number).
  static final _startPattern = RegExp(
    r'^start\s+(.+?)(?:\s+(\d{4}-\d{2}-\d{2}))?$',
    caseSensitive: false,
  );
  static final _updatePattern = RegExp(
    r'^update\s+(.+?)\s+(\d+)(?:\s+(\d{4}-\d{2}-\d{2}))?$',
    caseSensitive: false,
  );
  static final _finishPattern = RegExp(
    r'^finish\s+(.+?)(?:\s+(\d{4}-\d{2}-\d{2}))?$',
    caseSensitive: false,
  );
  static final _ratePattern = RegExp(
    r'^rate\s+(.+?)\s+(\d+(?:\.\d+)?)$',
    caseSensitive: false,
  );
  static final _deletePattern = RegExp(
    r'^delete\s+(.+)$',
    caseSensitive: false,
  );
  // "::" is the separator the parse-command prompt is told to always
  // emit for these two, precisely so a title with its own colon or
  // dash doesn't get split in the wrong place the way a bare space
  // would.
  static final _rememberPattern = RegExp(
    r'^remember\s+(.+?)\s*::\s*(.+)$',
    caseSensitive: false,
  );
  static final _recommendPattern = RegExp(
    r'^recommend\s+(.+?)\s*::\s*(.+)$',
    caseSensitive: false,
  );

  // Deliberately excludes `remember`/`recommend`: a free-plan reader
  // typing a manual command should never see a pro-only feature
  // suggested for a typo — those two are only ever recognized when the
  // AI itself emits the exact keyword.
  static const _firstWordPattern = r'^(\S+)';
  static const _keywords = ['start', 'update', 'finish', 'rate', 'delete'];
  static const _usage = {
    'start': 'start <book> [date]',
    'update': 'update <book> <page> [date]',
    'finish': 'finish <book> [date]',
    'rate': 'rate <book> <stars>',
    'delete': 'delete <book>',
    'remember': 'remember <book> :: <note>',
    'recommend': 'recommend <book> :: <reason>',
  };

  static ParsedLogCommand parse(String input) {
    final text = input.trim();
    if (text.isEmpty) {
      return const ParsedLogCommand(message: '', recognized: false);
    }

    final rate = _ratePattern.firstMatch(text);
    if (rate != null) {
      final title = rate.group(1)!.trim();
      final rawRating = double.tryParse(rate.group(2)!);
      // Half-star granularity — the library only ever renders full,
      // half, or empty stars, so a finer rating (4.3) would show as one
      // thing and be stored as another. Rounded here so the pill's own
      // optimistic message already matches what rateBook will save.
      final rating = rawRating == null ? null : _roundToHalfStar(rawRating);
      return ParsedLogCommand(
        message: rating == null ? '' : '"$title" — ${_formatStars(rating)}★',
        recognized: true,
        type: LogCommandType.rate,
        title: title,
        rating: rating,
      );
    }

    final update = _updatePattern.firstMatch(text);
    if (update != null) {
      final title = update.group(1)!.trim();
      final page = update.group(2)!;
      final date = _parseDate(update.group(3));
      return ParsedLogCommand(
        message: '"$title" — pg $page${_dateSuffix(date)}',
        recognized: true,
        type: LogCommandType.update,
        title: title,
        // The pattern guarantees digits only; tryParse still guards the
        // one case it can't — a number too large for an int.
        page: int.tryParse(page),
        date: date,
      );
    }

    final finish = _finishPattern.firstMatch(text);
    if (finish != null) {
      final title = finish.group(1)!.trim();
      final date = _parseDate(finish.group(2));
      return ParsedLogCommand(
        message: 'Finished "$title"${_dateSuffix(date)}',
        recognized: true,
        type: LogCommandType.finish,
        title: title,
        date: date,
      );
    }

    final start = _startPattern.firstMatch(text);
    if (start != null) {
      final title = start.group(1)!.trim();
      final date = _parseDate(start.group(2));
      return ParsedLogCommand(
        message: 'Started "$title"${_dateSuffix(date)}',
        recognized: true,
        type: LogCommandType.start,
        title: title,
        date: date,
      );
    }

    final delete = _deletePattern.firstMatch(text);
    if (delete != null) {
      final title = delete.group(1)!.trim();
      return ParsedLogCommand(
        message: 'Removed "$title"',
        recognized: true,
        type: LogCommandType.delete,
        title: title,
      );
    }

    final remember = _rememberPattern.firstMatch(text);
    if (remember != null) {
      final title = remember.group(1)!.trim();
      final note = remember.group(2)!.trim();
      return ParsedLogCommand(
        message: 'Remembered "$title" — $note',
        recognized: true,
        type: LogCommandType.remember,
        title: title,
        note: note,
      );
    }

    final recommend = _recommendPattern.firstMatch(text);
    if (recommend != null) {
      final title = recommend.group(1)!.trim();
      final reason = recommend.group(2)!.trim();
      return ParsedLogCommand(
        message: '"$title" — $reason',
        recognized: true,
        type: LogCommandType.recommend,
        title: title,
        note: reason,
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
        '"finish Dune", "rate Dune 5", or "delete Dune". Add a date — '
        '"start Dune 2026-08-31" — to log it for another day.';
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Parses a `YYYY-MM-DD` regex capture into a plain calendar date, or
  /// null if [raw] is null (no date was given) — `DateTime.parse`'s own
  /// leniency is more than this needs, but the pattern already
  /// guarantees the shape, so there is nothing left for it to reject.
  static DateTime? _parseDate(String? raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  /// " — Aug 31" for a backdated command's pill, or "" for one logged
  /// just now — kept separate from the base message so every caller
  /// gets the exact same short format rather than three near-identical
  /// ones.
  static String _dateSuffix(DateTime? date) {
    if (date == null) return '';
    return ' — ${_months[date.month - 1]} ${date.day}';
  }

  static double _roundToHalfStar(double value) => (value * 2).round() / 2;

  /// Drops a trailing ".0" ("5★" rather than "5.0★") but keeps a real
  /// half ("4.5★") — matches how the library's star row reads a rating.
  static String _formatStars(double rating) {
    return rating == rating.roundToDouble()
        ? rating.toInt().toString()
        : rating.toStringAsFixed(1);
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
      final maxLength = word.length > keyword.length
          ? word.length
          : keyword.length;
      final similarity = maxLength == 0 ? 0.0 : 1 - (distance / maxLength);
      if (similarity > bestSimilarity) {
        bestSimilarity = similarity;
        best = keyword;
      }
    }
    return (best != null && bestSimilarity >= _similarityThreshold)
        ? best
        : null;
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
        dp[i][j] = [
          deletion,
          insertion,
          substitution,
        ].reduce((x, y) => x < y ? x : y);
      }
    }
    return dp[rows - 1][cols - 1];
  }
}
