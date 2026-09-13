import 'command_catalog.dart';

// Zero-cost, rule-based parser for Structured mode commands:
// `start <book> [date]`, `update <book> <page> [date]`,
// `update <book> <percent>% [date]`, `finish <book> [date]`,
// `rate <book> <stars>`, `delete <book>`,
// `add shelf <tbr|reading|finished|dnf> <book>`, `add tag <tag> <book>`,
// `add comment <comment> <book>`, `series <series> [#n] <book>` and
// `start series <series>` — the optional trailing date
// (`YYYY-MM-DD`) on the first three backdates the reading event it
// logs, so "I started Dune yesterday" (resolved to a concrete date by
// cactus pro before it ever reaches this parser) logs — and streaks —
// on that day rather than today. Plus two "cactus pro"-only commands
// that only ever arrive as an AI-extracted line, never typed directly:
// `remember <book> :: <note>` and `recommend <book> :: <reason>`.
// Recognizing their syntax here doesn't make them free-plan features —
// `HomePage` gates both behind `PlanController.isPro` at the point they'd
// actually run, the same way every other pro-only surface in the app is
// gated.
//
// The `add` family puts its own argument (the shelf, the tag, the
// comment) *before* the book, so the title is always the free-form tail
// of the line and never needs a terminator. Help text for every command
// lives in [CommandCatalog], not here.
enum LogCommandType {
  start,
  update,
  finish,
  rate,
  delete,

  /// `add shelf <shelf> <book>`.
  addShelf,

  /// `add tag <tag> <book>`.
  addTag,

  /// `add comment <comment> <book>`.
  addComment,

  /// `series <series> [#n] <book>`.
  series,

  /// `start series <series>`.
  startSeries,
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
    this.shelf,
    this.percent,
    this.tag,
    this.series,
    this.seriesPosition,
  });

  /// Confirmation (or error/suggestion) text for the pill.
  final String message;
  final bool recognized;

  final LogCommandType type;

  /// The book the command refers to — null when unrecognized. For
  /// `recommend` this is the *recommended* title, not one already on
  /// the shelf. Also null for an *unquoted* `add comment`, where only the
  /// shelf can tell where the comment ends and the title begins — see
  /// [note].
  final String? title;

  /// Page argument of `update`. Always a non-negative int when present;
  /// the pattern only matches digits, so no sign or decimal can get in.
  /// Null when `update` was given a [percent] instead of a raw page.
  final int? page;

  /// The `<percent>` in `update <book> <percent>%` — an alternative to
  /// [page] for a reader who thinks in "74%" rather than a raw page
  /// number. Resolved to an actual page by `LibraryController`, which is
  /// the only place that knows the book's total page count. Null for
  /// every other command, and for `update` given a plain page instead.
  final double? percent;

  /// Star argument of `rate`.
  final double? rating;

  /// The free-text half of `remember` (the note itself), `recommend`
  /// (why that book) or `add comment` (the comment) — null for every
  /// other command.
  ///
  /// For `add comment` without quotes ("add comment loved it Dune") this
  /// is the *whole* argument, comment and title together, and [title] is
  /// null: `LibraryController.addComment` splits it against the titles
  /// actually on the shelf.
  final String? note;

  /// The optional trailing `YYYY-MM-DD` on `start`/`update`/`finish` —
  /// "I started Dune yesterday" resolves to this, on cactus pro, before
  /// ever reaching this parser (see `parse-command`'s prompt). Null
  /// means "just now", same as before this existed. A plain calendar
  /// date with no time component — callers that persist it should
  /// treat it as local midnight on that day, not UTC.
  final DateTime? date;

  /// `tbr`, `reading`, `finished` or `dnf` on `add shelf` — the raw
  /// keyword, lowercased, not a `ReadingStatus`, so this file stays free
  /// of any dependency on the library feature's domain;
  /// `HomePage._applyToLibrary` is what maps it to one. Null for every
  /// other command.
  final String? shelf;

  /// The tag of `add tag`, surrounding quotes removed. Null for every
  /// other command.
  final String? tag;

  /// The series name of `series` and `start series`, quotes removed.
  final String? series;

  /// The optional `#n` of `series` — 1, 2, or 1.5 for a novella.
  final double? seriesPosition;
}

abstract final class LogCommandParser {
  // Optional trailing `YYYY-MM-DD` on these three — lazy title capture
  // means it always tries the *shortest* title first, so "start Dune
  // 2026-08-31" splits into title "Dune" + date, rather than the date
  // getting swallowed into the title (same reasoning `_updatePattern`
  // already relies on for its own trailing number).
  // `start series <series>` — checked before `start <book>`, which would
  // otherwise read "series dune" as a title. The series name is the whole
  // rest of the line, quoted or not.
  static final _startSeriesPattern = RegExp(
    r'^start\s+series\s+(?:"([^"]+)"|“([^”]+)”|(.+))$',
    caseSensitive: false,
  );
  // `series <series> [#n] <book>` — one word, or a quoted name, like a tag;
  // an optional `#2` numbers the book within the series.
  static final _seriesPattern = RegExp(
    r'^series\s+(?:"([^"]+)"|“([^”]+)”|(\S+))(?:\s+#(\d+(?:\.\d)?))?\s+(.+)$',
    caseSensitive: false,
  );
  static final _startPattern = RegExp(
    r'^start\s+(.+?)(?:\s+(\d{4}-\d{2}-\d{2}))?$',
    caseSensitive: false,
  );
  static final _updatePattern = RegExp(
    r'^update\s+(.+?)\s+(\d+)(?:\s+(\d{4}-\d{2}-\d{2}))?$',
    caseSensitive: false,
  );
  // Same shape as `_updatePattern`, but the number is followed by a
  // trailing `%` — checked first (see `parse`) since the plain-page
  // pattern above would otherwise swallow the digits and leave the `%`
  // unmatched, failing the whole line instead of falling through.
  static final _updatePercentPattern = RegExp(
    r'^update\s+(.+?)\s+(\d+(?:\.\d+)?)\s*%(?:\s+(\d{4}-\d{2}-\d{2}))?$',
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
  // `add shelf <shelf> <book>` — the shelf is a closed set of keywords,
  // so everything after it is the title, whatever words that contains.
  static final _addShelfPattern = RegExp(
    '^add\\s+shelf\\s+(${CommandCatalog.shelves.join('|')})\\s+(.+)\$',
    caseSensitive: false,
  );
  // `add tag <tag> <book>` — one word, or a longer tag in straight or
  // curly double quotes. (Never single quotes: an apostrophe belongs to
  // plenty of real tags and titles.)
  static final _addTagPattern = RegExp(
    r'^add\s+tag\s+(?:"([^"]+)"|“([^”]+)”|(\S+))\s+(.+)$',
    caseSensitive: false,
  );
  // `add comment "<comment>" <book>` — the quoted form, where the split
  // between comment and title is unambiguous and made right here.
  static final _addCommentQuotedPattern = RegExp(
    r'^add\s+comment\s+(?:"([^"]+)"|“([^”]+)”)\s+(.+)$',
    caseSensitive: false,
  );
  // `add comment <comment> <book>` without quotes — at least two words,
  // split later by the library (see [ParsedLogCommand.note]). Must not
  // start with a quote: a quote that never closed (or closed on nothing)
  // is a mistyped quoted comment, not an unquoted one to save verbatim.
  static final _addCommentPattern = RegExp(
    r'^add\s+comment\s+([^"“\s]\S*(?:\s+\S+)+)$',
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
  static const _keywords = [
    'start',
    'update',
    'finish',
    'rate',
    'delete',
    'add',
    'series',
  ];

  /// The second word of the `add` family — used to pick which of the three
  /// usages to suggest for a mistyped `add` line.
  static const _addKinds = ['shelf', 'tag', 'comment'];

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

    final updatePercent = _updatePercentPattern.firstMatch(text);
    if (updatePercent != null) {
      final title = updatePercent.group(1)!.trim();
      final percent = double.tryParse(updatePercent.group(2)!);
      final date = _parseDate(updatePercent.group(3));
      return ParsedLogCommand(
        message: percent == null
            ? ''
            : '"$title" — ${_formatPercent(percent)}%${_dateSuffix(date)}',
        recognized: true,
        type: LogCommandType.update,
        title: title,
        percent: percent,
        date: date,
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

    final startSeries = _startSeriesPattern.firstMatch(text);
    if (startSeries != null) {
      final name =
          (startSeries.group(1) ??
                  startSeries.group(2) ??
                  startSeries.group(3))!
              .trim();
      if (name.isNotEmpty) {
        return ParsedLogCommand(
          // The book isn't known until the library looks the series up, so
          // the pill uses the library's message instead.
          message: 'Started the next book in $name',
          recognized: true,
          type: LogCommandType.startSeries,
          series: name,
        );
      }
    }

    final series = _seriesPattern.firstMatch(text);
    if (series != null) {
      final name = (series.group(1) ?? series.group(2) ?? series.group(3))!
          .trim();
      final position = series.group(4) == null
          ? null
          : double.tryParse(series.group(4)!);
      final title = series.group(5)!.trim();
      if (name.isNotEmpty && (series.group(4) == null || position != null)) {
        final number = position == null ? '' : ' #${_formatStars(position)}';
        return ParsedLogCommand(
          message: 'Filed "$title" under $name$number',
          recognized: true,
          type: LogCommandType.series,
          title: title,
          series: name,
          seriesPosition: position,
        );
      }
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

    final addShelf = _addShelfPattern.firstMatch(text);
    if (addShelf != null) {
      final shelf = addShelf.group(1)!.toLowerCase();
      final title = addShelf.group(2)!.trim();
      return ParsedLogCommand(
        message: switch (shelf) {
          'finished' => 'Added "$title" as finished',
          'dnf' => 'Marked "$title" as DNF',
          'reading' => 'Moved "$title" to reading',
          _ => 'Added "$title" to read',
        },
        recognized: true,
        type: LogCommandType.addShelf,
        title: title,
        shelf: shelf,
      );
    }

    final addTag = _addTagPattern.firstMatch(text);
    if (addTag != null) {
      final tag = (addTag.group(1) ?? addTag.group(2) ?? addTag.group(3))!
          .trim();
      final title = addTag.group(4)!.trim();
      // `"  "` quotes around nothing but space match the pattern but are
      // not a tag; fall through to the "did you mean" suggestion.
      if (tag.isNotEmpty) {
        return ParsedLogCommand(
          message: 'Tagged "$title" $tag',
          recognized: true,
          type: LogCommandType.addTag,
          title: title,
          tag: tag,
        );
      }
    }

    final quotedComment = _addCommentQuotedPattern.firstMatch(text);
    if (quotedComment != null) {
      final comment = (quotedComment.group(1) ?? quotedComment.group(2))!
          .trim();
      final title = quotedComment.group(3)!.trim();
      if (comment.isNotEmpty) {
        return ParsedLogCommand(
          message: 'Commented on "$title"',
          recognized: true,
          type: LogCommandType.addComment,
          title: title,
          note: comment,
        );
      }
    }

    // Checked after the quoted form: a quoted comment also matches this
    // looser pattern, and would lose its split if it got here first.
    final comment = _addCommentPattern.firstMatch(text);
    if (comment != null && quotedComment == null) {
      return ParsedLogCommand(
        // The book isn't known until the library splits the line, so the
        // optimistic message can't name it. A failed split reports the
        // library's own message instead of this one.
        message: 'Comment saved',
        recognized: true,
        type: LogCommandType.addComment,
        note: comment.group(1)!.trim(),
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
  /// distance) and suggests its usage from [CommandCatalog] — for `add`,
  /// the second word picks which of shelf/tag/comment. Falls back to a
  /// generic hint.
  static String _suggestionFor(String text) {
    final words = text.split(RegExp(r'\s+'));
    final closest = _closest(words.first.toLowerCase(), _keywords);
    if (closest != null) {
      var keyword = closest;
      if (closest == 'start' &&
          words.length > 1 &&
          words[1].toLowerCase() == 'series') {
        keyword = 'start series';
      } else if (closest == 'add') {
        final kind = words.length > 1
            ? _closest(words[1].toLowerCase(), _addKinds)
            : null;
        keyword = 'add ${kind ?? 'shelf'}';
      }
      final usage = CommandCatalog.byKeyword(keyword)?.syntax;
      if (usage != null) return 'Not recognized. Did you mean "$usage"?';
    }
    return 'Not recognized. Try "start Dune", "update Dune 120" (or '
        '"update Dune 74%"), "finish Dune", "rate Dune 5", "delete Dune", '
        '"add shelf tbr Dune", "add tag sci-fi Dune", "add comment '
        'loved it Dune" or "series dune #1 Dune". Settings → commands '
        'lists them all.';
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

  /// Drops a trailing ".0" ("74%" rather than "74.0%") but keeps a real
  /// fraction ("74.5%") — same convention as [_formatStars].
  static String _formatPercent(double percent) {
    return percent == percent.roundToDouble()
        ? percent.toInt().toString()
        : percent.toStringAsFixed(1);
  }

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

  static String? _closest(String word, List<String> candidates) {
    String? best;
    var bestSimilarity = 0.0;
    for (final keyword in candidates) {
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
