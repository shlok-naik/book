import 'dart:math' as math;

import '../../library/domain/library_search.dart';
import 'log_command_parser.dart';

/// A book on the reader's shelf, as far as [SmartCommandParser] needs to
/// know it. Listed most recently active first — the shelf's natural order.
class SmartBook {
  const SmartBook({
    required this.title,
    required this.author,
    this.isReading = false,
  });

  final String title;
  final String author;
  final bool isReading;
}

/// One action [SmartCommandParser] found in a message.
sealed class SmartLine {
  const SmartLine();
}

/// A line in [LogCommandParser]'s own grammar, ready to run.
final class ResolvedLine extends SmartLine {
  const ResolvedLine(this.command);

  final String command;

  @override
  bool operator ==(Object other) =>
      other is ResolvedLine && other.command == command;

  @override
  int get hashCode => command.hashCode;

  @override
  String toString() => 'ResolvedLine($command)';
}

/// An action whose book the reader didn't name, or named too loosely to be
/// sure of ("finish harry potter" with three on the shelf). The caller asks
/// — the book picker — then builds the line with [commandFor].
final class NeedsBookLine extends SmartLine {
  const NeedsBookLine(this._build, {required this.query});

  /// What the reader typed for the book, if anything — the picker's
  /// starting search.
  final String query;
  final String Function(String title) _build;

  String commandFor(String title) => _build(title);

  @override
  String toString() => 'NeedsBookLine($query)';
}

/// Nothing actionable — run as typed, so it fails with the parser's own
/// "didn't recognize" message and suggestion.
final class UnrecognizedLine extends SmartLine {
  const UnrecognizedLine(this.text);

  final String text;

  @override
  String toString() => 'UnrecognizedLine($text)';
}

/// The beta parser: plain sentences into [LogCommandParser]'s grammar,
/// entirely on the device, for every reader.
///
/// No model — patterns and a little arithmetic:
///
/// 1. **Split** the message into actions on sentence ends, "and", "then" and
///    commas — but only where the next piece says something to do, so
///    "Pride and Prejudice" stays one title.
/// 2. **Recognise** each action from the words readers actually use:
///    "started", "on page 40", "halfway", "done with", "gave up on", "loved
///    it, 4 stars", "want to read", "reading it again", "get rid of".
/// 3. **Pull out** pages, percentages, star ratings and dates ("yesterday",
///    "last night", "3 days ago", "on monday", an ISO date).
/// 4. **Match the title** against the shelf, forgiving typos (one edit in a
///    word of four letters or more, two from eight), ignoring "the"/"a" and
///    the author's own name ("dune by frank herbert"). "it"/"this book"
///    means the book just mentioned, else the one being read. A clear match
///    becomes the shelf's exact title; nothing on the shelf close enough
///    passes the words through for Google Books to find (the library adds
///    it); several close matches ask ([NeedsBookLine]) — unless one of
///    them is the book being read, which wins.
///
/// 5. **Organise** the library in plain words too: make shelves, tags and
///    series, tag a book, file it in a series with its number, comment on
///    it, or move it onto a shelf that exists ([shelves]).
///
/// A line that's already a command ("finish Dune") runs exactly as typed.
abstract final class SmartCommandParser {
  static List<SmartLine> parse(
    String message, {
    required List<SmartBook> library,
    required DateTime today,
    List<String> shelves = const [],
  }) {
    final text = message.trim();
    if (text.isEmpty) return const [];
    // "move dune to summer reads" is also a valid classic line — with the
    // title "dune to" — so plain-words organising is tried first.
    if (LogCommandParser.parse(text).recognized &&
        _parseOrganise(
              text,
              library: library,
              shelves: shelves,
              lastTitle: null,
            ) ==
            null) {
      return [_polishCommand(text, library)];
    }

    final lines = <SmartLine>[];
    String? lastTitle;
    for (final clause in _clauses(_joinHalves(text))) {
      final organised = _parseOrganise(
        clause,
        library: library,
        shelves: shelves,
        lastTitle: lastTitle,
      );
      if (organised != null) {
        lines.add(organised.$1);
        lastTitle = organised.$2 ?? lastTitle;
        continue;
      }
      if (LogCommandParser.parse(clause).recognized) {
        lines.add(_polishCommand(clause, library));
        continue;
      }
      final line = _parseClause(
        clause,
        library: library,
        today: today,
        lastTitle: lastTitle,
      );
      if (line case (final SmartLine parsed, final String? title)) {
        lines.add(parsed);
        lastTitle = title ?? lastTitle;
      } else {
        lines.add(UnrecognizedLine(clause));
      }
    }
    return lines;
  }

  /// A line that's already a command, with its book matched against the
  /// shelf the same forgiving way a sentence's is — "finish dnue" finishes
  /// *Dune*, and "finish harry potter" with three on the shelf asks.
  static SmartLine _polishCommand(String command, List<SmartBook> library) {
    final parsed = LogCommandParser.parse(command);
    final title = parsed.title;
    const bookCommands = {
      LogCommandType.start,
      LogCommandType.update,
      LogCommandType.finish,
      LogCommandType.restart,
      LogCommandType.rate,
      LogCommandType.delete,
    };
    if (title == null || !bookCommands.contains(parsed.type)) {
      return ResolvedLine(command);
    }
    final at = command.indexOf(title);
    if (at < 0) return ResolvedLine(command);
    String build(String replacement) =>
        command.replaceRange(at, at + title.length, replacement);
    return switch (_resolveTitle(title, library, null)) {
      _Title(:final title) => ResolvedLine(build(title)),
      _Ask(:final query) => NeedsBookLine(build, query: query),
    };
  }

  /// "four and a half" → "4.5", before splitting on "and" would cut a
  /// rating in two.
  static String _joinHalves(String text) => text.replaceAllMapped(
    RegExp(
      r'\b(\d|zero|one|two|three|four|five) and a half\b',
      caseSensitive: false,
    ),
    (m) {
      final word = m.group(1)!.toLowerCase();
      return '${_numberWords[word] ?? word}.5';
    },
  );

  // ---------------------------------------------------------------- clauses

  /// Full stops end a sentence — except inside a number ("4.5 stars").
  static final _sentenceBreak = RegExp(r'(?:(?<!\d)\.|\.(?!\d)|[;!?\n])+\s*');
  static final _joiner = RegExp(
    r'\s*,\s*(?:and\s+then\s+|and\s+|then\s+)?|\s+(?:and\s+then|then|and\s+also|also|and)\s+',
    caseSensitive: false,
  );

  static List<String> _clauses(String text) {
    final clauses = <String>[];
    for (final sentence in text.split(_sentenceBreak)) {
      if (sentence.trim().isEmpty) continue;
      final pieces = sentence.split(_joiner);
      final separators = _joiner
          .allMatches(sentence)
          .map((m) => m.group(0)!)
          .toList();
      var current = pieces.first;
      for (var i = 1; i < pieces.length; i++) {
        final piece = pieces[i];
        if (_intentOf(piece) != null ||
            _startsWithCommand(piece) ||
            _organiseStart.hasMatch(piece)) {
          clauses.add(current.trim());
          current = piece;
        } else {
          // Not an action of its own — part of a title ("Pride and
          // Prejudice") or a trailing detail; glue it back.
          current = '$current${separators[i - 1]}$piece';
        }
      }
      clauses.add(current.trim());
    }
    return [
      for (final clause in clauses)
        if (clause.isNotEmpty) clause,
    ];
  }

  static bool _startsWithCommand(String piece) => RegExp(
    r'^\s*(start|update|finish|restart|rate|delete|move|make|add|remove)\s',
    caseSensitive: false,
  ).hasMatch(piece);

  // ---------------------------------------------------------- organising

  /// A piece that starts organising the library — worth splitting on.
  static final _organiseStart = RegExp(
    r'^\s*(?:please\s+)?(?:make|create|new|tag|note|comment|put|file|move)\b',
    caseSensitive: false,
  );

  static final _makePattern = RegExp(
    r'^(?:please\s+)?(?:(?:make|create|start)\s+(?:me\s+)?(?:a\s+|an\s+)?'
    r'(?:new\s+)?|new\s+)(shelf|tag|series)\s+(?:called\s+|named\s+)?'
    r'["“]?(.+?)["”]?$',
    caseSensitive: false,
  );
  static final _tagAsPattern = RegExp(
    r'^tag\s+(.+?)\s+(?:as|with)\s+(?:a\s+)?["“]?(.+?)["”]?$',
    caseSensitive: false,
  );
  static final _addTagPattern = RegExp(
    r'^add\s+(?:the\s+|a\s+)?(?:tag\s+)?["“]?(.+?)["”]?(?:\s+tag)?\s+(?:to|on)\s+(.+)$',
    caseSensitive: false,
  );
  static final _seriesPattern = RegExp(
    r'^(?:add|put|file)\s+(.+?)\s+(?:in|into|to|under)\s+(?:the\s+|my\s+)?'
    r'["“]?(.+?)["”]?\s+series(?:\s+(?:as\s+)?(?:#|number\s+|book\s+|no\.?\s*)'
    r'(\d+))?$',
    caseSensitive: false,
  );
  static final _commentPattern = RegExp(
    r'^(?:add\s+(?:a\s+)?)?(?:comment|note)\s+(?:on|to|for)\s+(.+?)'
    r'(?:\s*:\s*|\s+that\s+|\s+saying\s+)(.+)$',
    caseSensitive: false,
  );
  static final _movePattern = RegExp(
    r'^(?:move|put)\s+(.+?)\s+(?:on|onto|to|in|into)\s+(?:the\s+|my\s+)?'
    r'["“]?(.+?)["”]?(?:\s+shelf)?$',
    caseSensitive: false,
  );

  static const _builtInShelves = {
    'reading',
    'to read',
    'tbr',
    'finished',
    'dnf',
    'did not finish',
  };

  /// Making shelves, tags and series, and filing books into them, in plain
  /// words: "make a shelf called summer reads", "tag dune as sci-fi", "add
  /// cosy to circe", "put dune messiah in the dune series as #2", "note on
  /// dune: the ending got me", "move dune to summer reads". Null when the
  /// clause isn't one of these.
  static (SmartLine, String?)? _parseOrganise(
    String clause, {
    required List<SmartBook> library,
    required List<String> shelves,
    required String? lastTitle,
  }) {
    final text = clause.trim().replaceAll(RegExp(r'[.!]+$'), '');
    String clean(String name) =>
        name.trim().replaceAll('"', '').replaceAll('“', '').replaceAll('”', '');
    (SmartLine, String?) withBook(
      String phrase,
      String Function(String title) build,
    ) {
      final words = phrase.trim().toLowerCase().replaceAll(
        RegExp(r'^(?:the book\s+|my\s+)'),
        '',
      );
      return switch (_resolveTitle(words, library, lastTitle)) {
        _Title(:final title) => (ResolvedLine(build(title)), title),
        _Ask(:final query) => (NeedsBookLine(build, query: query), null),
      };
    }

    if (_makePattern.firstMatch(text) case final m?) {
      final name = clean(m.group(2)!);
      if (name.isEmpty) return null;
      return (ResolvedLine('make ${m.group(1)!.toLowerCase()} $name'), null);
    }
    if (_seriesPattern.firstMatch(text) case final m?) {
      final name = clean(m.group(2)!);
      final number = m.group(3);
      return withBook(
        m.group(1)!,
        (title) =>
            'add series "$name"${number == null ? '' : ' #$number'} '
            '$title',
      );
    }
    if (_commentPattern.firstMatch(text) case final m?) {
      final comment = clean(m.group(2)!);
      if (comment.isEmpty) return null;
      return withBook(m.group(1)!, (title) => 'add comment "$comment" $title');
    }
    if (_tagAsPattern.firstMatch(text) case final m?) {
      final tag = clean(m.group(2)!);
      return withBook(m.group(1)!, (title) => 'add tag "$tag" $title');
    }
    if (_movePattern.firstMatch(text) case final m?) {
      final shelf = clean(m.group(2)!);
      final key = shelf.toLowerCase();
      final known =
          _builtInShelves.contains(key) ||
          shelves.any((s) => s.toLowerCase() == key);
      // "put dune on my to read" is a shelf; "put the kettle on" is not.
      if (known) {
        return withBook(m.group(1)!, (title) => 'move $title "$shelf"');
      }
    }
    if (_addTagPattern.firstMatch(text) case final m?) {
      final tag = clean(m.group(1)!);
      final key = tag.toLowerCase();
      // "add dune to my to read" is a shelf move, not a tag called dune.
      if (!key.contains(' ') &&
          !_builtInShelves.contains(clean(m.group(2)!).toLowerCase()) &&
          !RegExp(r'\b(?:list|shelf|library|tbr)\b').hasMatch(m.group(2)!)) {
        return withBook(m.group(2)!, (title) => 'add tag "$tag" $title');
      }
    }
    return null;
  }

  // ---------------------------------------------------------------- intents

  static final _intents = <(_Intent, RegExp)>[
    (
      _Intent.delete,
      RegExp(
        r'\b(delete|get rid of|remove(?=.*\bfrom (?:my )?(?:library|shelf|books)\b)|take .* off my (?:shelf|library))\b',
      ),
    ),
    (
      _Intent.restart,
      RegExp(
        r'\b(re-?read(?:ing)?|re-?start(?:ed|ing)?|(?:reading|read|started|starting|start) .*\bagain|again)\b',
      ),
    ),
    (
      _Intent.dnf,
      RegExp(
        r"\b(gave up(?: on)?|give up(?: on)?|giving up(?: on)?|dnf(?:'?d)?|abandon(?:ed|ing)?|stopped reading|quit(?:ting)?|couldn'?t finish|did not finish|didn'?t finish)\b",
      ),
    ),
    (
      _Intent.toRead,
      RegExp(
        r'\b(want to read|wanna read|to read list|reading list|tbr|to-read|queue(?:d)?|add(?:ed)? .*\bto (?:my |the )?(?:list|shelf|library|to read))\b',
      ),
    ),
    (
      _Intent.rate,
      RegExp(
        r'\b(rat(?:e|ed|ing)|stars?|out of (?:5|five))\b|\d(?:\.5)?\s*/\s*5',
      ),
    ),
    (
      _Intent.finish,
      RegExp(
        r'\b(finish(?:ed|ing)?|done (?:with|reading)|complet(?:e|ed)|read the (?:whole|entire) (?:thing|book)|reached the end|last page)\b',
      ),
    ),
    (
      _Intent.update,
      RegExp(
        r'\b(pages?|pgs?|p\.|percent|halfway|half way|a third|a quarter|'
        r'three quarters|through)\b|\d+\s*%',
      ),
    ),
    (
      _Intent.start,
      RegExp(
        r"\b(start(?:ed|ing)?|began|begin(?:ning)?|picked up|picking up|(?:i'?m|am|now) reading|currently reading|reading)\b",
      ),
    ),
  ];

  static _Intent? _intentOf(String clause) {
    final lower = clause.toLowerCase();
    for (final (intent, pattern) in _intents) {
      if (pattern.hasMatch(lower)) return intent;
    }
    return null;
  }

  // ------------------------------------------------------------ one clause

  static (SmartLine, String?)? _parseClause(
    String clause, {
    required List<SmartBook> library,
    required DateTime today,
    required String? lastTitle,
  }) {
    final spelled = _digits(clause);
    final intent = _intentOf(spelled);
    if (intent == null) return null;
    var lower = ' ${spelled.toLowerCase()} ';

    // Dates first: "yesterday" must not be mistaken for part of a title.
    final (date, withoutDate) = _takeDate(lower, today);
    // A day that doesn't exist ("2026-02-31") isn't quietly moved to one
    // that does: the line runs as typed and is refused for its date.
    if (identical(date, _invalidDate)) return null;
    lower = withoutDate;
    final dateSuffix = date == null ? '' : ' ${_iso(date)}';

    String? detail;
    switch (intent) {
      case _Intent.rate:
        final (stars, rest) = _takeStars(lower);
        if (stars == null) return null;
        detail = stars;
        lower = rest;
      case _Intent.update:
        final (progress, rest) = _takeProgress(lower);
        if (progress == null) return null;
        detail = progress;
        lower = rest;
      default:
        break;
    }

    final phrase = _titlePhrase(lower, intent);
    String build(String title) => switch (intent) {
      _Intent.start => 'start $title$dateSuffix',
      _Intent.update => 'update $title $detail$dateSuffix',
      _Intent.finish => 'finish $title$dateSuffix',
      _Intent.restart => 'restart $title$dateSuffix',
      _Intent.rate => 'rate $title $detail',
      _Intent.delete => 'delete $title',
      _Intent.dnf => 'move $title "dnf"',
      _Intent.toRead => 'move $title "tbr"',
    };

    final resolved = _resolveTitle(phrase, library, lastTitle);
    return switch (resolved) {
      _Title(:final title) => (ResolvedLine(build(title)), title),
      _Ask(:final query) => (NeedsBookLine(build, query: query), null),
    };
  }

  /// Numbers a reader writes out — "twenty pages", "thirty more pages".
  /// Only whole tens and their teens: past that ("a hundred and twelve")
  /// nobody spells it out, and guessing would be worse than asking.
  static const _spelledPages = {
    'one': '1',
    'two': '2',
    'three': '3',
    'four': '4',
    'five': '5',
    'six': '6',
    'seven': '7',
    'eight': '8',
    'nine': '9',
    'ten': '10',
    'eleven': '11',
    'twelve': '12',
    'thirteen': '13',
    'fourteen': '14',
    'fifteen': '15',
    'sixteen': '16',
    'seventeen': '17',
    'eighteen': '18',
    'nineteen': '19',
    'twenty': '20',
    'thirty': '30',
    'forty': '40',
    'fifty': '50',
    'sixty': '60',
    'seventy': '70',
    'eighty': '80',
    'ninety': '90',
    'hundred': '100',
    'a hundred': '100',
  };

  /// [clause] with any spelled-out number turned into digits, so the page
  /// patterns below only ever have one form to read. Left alone where it
  /// would change a title: only a number followed immediately by "pages"
  /// is rewritten, so "Two Towers" and "four and a half stars" are safe
  /// ([_takeStars] has its own, smaller list for star words).
  static String _digits(String clause) {
    var text = clause;
    for (final MapEntry(:key, :value) in _spelledPages.entries) {
      text = text.replaceAllMapped(
        RegExp('\\b$key\\s+(pages?|pgs?)\\b', caseSensitive: false),
        (match) => '$value ${match.group(1)}',
      );
    }
    return text;
  }

  // ------------------------------------------------------------------ dates

  static const _weekdays = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  /// What [_takeDate] returns for an ISO date naming no real day.
  static final _invalidDate = DateTime.utc(0);

  static (DateTime?, String) _takeDate(String text, DateTime today) {
    final day = DateTime(today.year, today.month, today.day);

    final iso = RegExp(
      r'\b(?:on\s+)?(\d{4})-(\d{2})-(\d{2})\b',
    ).firstMatch(text);
    if (iso != null) {
      final date = LogCommandParser.parseIsoDate(
        '${iso.group(1)}-${iso.group(2)}-${iso.group(3)}',
      );
      return (date ?? _invalidDate, text.replaceRange(iso.start, iso.end, ' '));
    }

    final patterns = <(RegExp, DateTime? Function(RegExpMatch))>[
      (
        RegExp(r'\b(yesterday|last night)\b'),
        (_) => day.subtract(const Duration(days: 1)),
      ),
      (RegExp(r'\b(today|tonight|this morning)\b'), (_) => null),
      (
        RegExp(r'\b(\d+|a|one|two|three|four|five|six) days? ago\b'),
        (m) {
          const words = {
            'a': 1,
            'one': 1,
            'two': 2,
            'three': 3,
            'four': 4,
            'five': 5,
            'six': 6,
          };
          final n = int.tryParse(m.group(1)!) ?? words[m.group(1)!] ?? 1;
          return day.subtract(Duration(days: n));
        },
      ),
      (
        RegExp(r'\b(?:last week)\b'),
        (_) => day.subtract(const Duration(days: 7)),
      ),
      (
        RegExp('\\b(?:on |last )?(${_weekdays.join('|')})\\b'),
        (m) {
          final target = _weekdays.indexOf(m.group(1)!) + 1;
          var back = (day.weekday - target) % 7;
          if (back == 0) back = 7;
          return day.subtract(Duration(days: back));
        },
      ),
    ];
    for (final (pattern, resolve) in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        return (resolve(match), text.replaceRange(match.start, match.end, ' '));
      }
    }
    return (null, text);
  }

  static String _iso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  // --------------------------------------------------- stars and progress

  static const _numberWords = {
    'zero': '0',
    'one': '1',
    'two': '2',
    'three': '3',
    'four': '4',
    'five': '5',
  };

  static (String?, String) _takeStars(String text) {
    var t = text;
    _numberWords.forEach((word, digit) {
      t = t.replaceAll(
        RegExp('\\b$word\\b(?=\\s*(?:and a half\\s*)?(?:stars?|/|out of))'),
        digit,
      );
    });
    final patterns = [
      RegExp(
        r'(\d(?:\.\d)?)(\s*and a half)?\s*(?:stars?|/\s*5|out of (?:5|five))',
      ),
      RegExp(
        r'\brat(?:e|ed|ing)\b(?:\s+it)?\s+(?:a\s+)?(\d(?:\.\d)?)(\s*and a half)?',
      ),
      RegExp(r'\b(\d(?:\.\d)?)(\s*and a half)?$'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(t.trim());
      if (match == null) continue;
      var stars = double.parse(match.group(1)!);
      if (match.group(2) != null) stars += 0.5;
      final value = stars == stars.roundToDouble()
          ? '${stars.toInt()}'
          : '$stars';
      final trimmed = t.trim();
      return (value, ' ${trimmed.replaceRange(match.start, match.end, ' ')} ');
    }
    return (null, text);
  }

  static (String?, String) _takeProgress(String text) {
    final fractions = <RegExp, String>{
      RegExp(r'\b(?:half ?way|half)(?: through)?\b'): '50%',
      RegExp(r'\ba third(?: of the way)?(?: through)?\b'): '33%',
      RegExp(r'\ba quarter(?: of the way)?(?: through)?\b'): '25%',
      RegExp(r'\bthree quarters(?: of the way)?(?: through)?\b'): '75%',
    };
    final percent = RegExp(
      r'(\d{1,3}(?:\.\d+)?)\s*(?:%|percent)(?: (?:through|done|of the way|in))?',
    ).firstMatch(text);
    if (percent != null) {
      return (
        '${percent.group(1)}%',
        text.replaceRange(percent.start, percent.end, ' '),
      );
    }
    for (final MapEntry(key: pattern, value: value) in fractions.entries) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        return (value, text.replaceRange(match.start, match.end, ' '));
      }
    }
    // "on page 24", "up to pg 24" — the page they are *on*.
    final page = RegExp(
      r'\b(?:(?:up )?(?:on|at|to|reached|hit|onto)\s+)?(?:page|pg|p\.)\s*(\d+)\b',
    ).firstMatch(text);
    if (page != null) {
      return (page.group(1), text.replaceRange(page.start, page.end, ' '));
    }
    // "100 pages in", "100 pages into dune" - how far in they *are*,
    // so absolute, unlike the "read 100 pages" below it.
    final into = RegExp(
      r'\b(\d+)\s*(?:pages?|pgs?)\s+(?:in|into)\b',
    ).firstMatch(text);
    if (into != null) {
      return (into.group(1), text.replaceRange(into.start, into.end, ' '));
    }
    // "read 24 pages", "another 30 pages", "24 more pages" — pages read
    // since last time, which is not the same thing, so it keeps the
    // grammar's `+` and the controller adds it to where the book was left.
    final more = RegExp(
      r'\b(?:another\s+)?(\d+)\s*(?:more\s+)?(?:pages?|pgs?)\b',
    ).firstMatch(text);
    if (more != null) {
      return (
        '+${more.group(1)}',
        text.replaceRange(more.start, more.end, ' '),
      );
    }
    return (null, text);
  }

  // ----------------------------------------------------------------- titles

  /// Words that say what to do, not which book — stripped wherever they
  /// appear, longest first.
  static final _actionWords = RegExp(
    r"\b(i'?m|i am|i'?ve|i have|i|just|finally|have|has|had|was|am|been|"
    r'currently|now|already|also|really|totally|'
    r'started|starting|start|began|begin|beginning|picked up|picking up|'
    r'reading|read|re-?reading|re-?read|re-?started|re-?starting|restart|again|'
    r'finished|finishing|finish|done with|done reading|done|completed|complete|'
    r'read the whole thing|read the entire book|reached the end of|reached the end|'
    r'got through|gotten through|made it through|got to|up to|another|more|'
    r'gave up on|gave up|give up on|giving up on|dnf|dnfed|abandoned|stopped reading|quit|'
    r"couldn'?t finish|did not finish|didn'?t finish|"
    r'want to read|wanna read|add(?:ed)?|to my|to the|my|to read list|reading list|tbr|to-read|list|queue|queued|'
    r'delete|deleted|get rid of|remove|removed|from my library|from my shelf|library|shelf|'
    r'rate|rated|rating|gave|give|stars?|out of|loved|liked|hated|enjoyed|'
    r'on page|at page|page|pages|through|of the way|in|into|'
    r'the book|this book|that book|book|novel)\b',
  );

  static String _titlePhrase(String text, _Intent intent) {
    var phrase = text.replaceAll(RegExp('[,:!?"“”]'), ' ');
    phrase = phrase.replaceAll(_actionWords, ' ');
    phrase = phrase.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Loose prepositions left at either end once the verbs are gone.
    const edges = {
      'on',
      'at',
      'to',
      'with',
      'of',
      'for',
      'it',
      'and',
      'the',
      'a',
      'an',
    };
    var words = phrase.split(' ').where((w) => w.isNotEmpty).toList();
    while (words.isNotEmpty &&
        edges.contains(words.first) &&
        words.first != 'it') {
      words.removeAt(0);
    }
    while (words.isNotEmpty &&
        edges.contains(words.last) &&
        words.last != 'it') {
      words.removeLast();
    }
    return words.join(' ');
  }

  static const _pronouns = {
    'it',
    'this',
    'that',
    'this one',
    'that one',
    'the one',
    'one',
  };

  static const _stopWords = {'the', 'a', 'an', 'and', 'of', 'by', '&'};

  static _Resolution _resolveTitle(
    String phrase,
    List<SmartBook> library,
    String? lastTitle,
  ) {
    SmartBook? reading;
    for (final book in library) {
      if (book.isReading) {
        reading = book;
        break;
      }
    }

    if (phrase.isEmpty || _pronouns.contains(phrase)) {
      if (lastTitle != null) return _Title(lastTitle);
      if (reading != null) return _Title(reading.title);
      return const _Ask('');
    }

    final scored = [for (final book in library) (book, _score(phrase, book))]
      ..sort((a, b) => b.$2.compareTo(a.$2));
    if (scored.isEmpty || scored.first.$2 < 0.6) {
      // Nothing on the shelf is close — let Google Books find it.
      return _Title(phrase);
    }
    final best = scored.first.$2;
    final close = [
      for (final (book, score) in scored)
        if (score >= 0.6 && best - score < 0.15) book,
    ];
    if (close.length == 1) return _Title(close.single.title);
    if (reading != null && close.contains(reading)) {
      return _Title(reading.title);
    }
    return _Ask(phrase);
  }

  static List<String> _tokens(String text) => LibrarySearch.normalize(text)
      .replaceAll(RegExp(r"[^a-z0-9' ]"), ' ')
      .split(' ')
      .where((w) => w.isNotEmpty && !_stopWords.contains(w))
      .toList();

  /// How well [phrase] names [book], 0–1: the share of the phrase's words
  /// found in the title, times the square root of the share of the title's
  /// words the phrase covers — so "dune" names *Dune* (1.0) better than
  /// *Dune Messiah* (0.71), and "harry potter" names each Harry Potter
  /// book equally. Words matching the author are ignored.
  static double _score(String phrase, SmartBook book) {
    final author = _tokens(book.author);
    final words = [
      for (final word in _tokens(phrase))
        if (!author.any((a) => _similar(a, word))) word,
    ];
    final title = _tokens(book.title.split(':').first);
    if (words.isEmpty || title.isEmpty) return 0;
    final found = words.where((w) => title.any((t) => _similar(t, w))).length;
    final covered = title.where((t) => words.any((w) => _similar(t, w))).length;
    if (found == 0) return 0;
    final share = covered / title.length;
    return (found / words.length) * math.sqrt(share);
  }

  /// Equal, or a typo apart: one edit in a word of four letters or more,
  /// two from eight. Transpositions count as one edit ("dnue" is "dune").
  static bool _similar(String a, String b) {
    if (a == b) return true;
    final shorter = a.length < b.length ? a.length : b.length;
    final allowed = shorter >= 8 ? 2 : (shorter >= 4 ? 1 : 0);
    if (allowed == 0 || (a.length - b.length).abs() > allowed) return false;
    return _editDistance(a, b) <= allowed;
  }

  /// Optimal string alignment distance.
  static int _editDistance(String a, String b) {
    final d = List.generate(
      a.length + 1,
      (i) => List<int>.generate(
        b.length + 1,
        (j) => i == 0 ? j : (j == 0 ? i : 0),
      ),
    );
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        var best = [
          d[i - 1][j] + 1,
          d[i][j - 1] + 1,
          d[i - 1][j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
        if (i > 1 &&
            j > 1 &&
            a[i - 1] == b[j - 2] &&
            a[i - 2] == b[j - 1] &&
            d[i - 2][j - 2] + 1 < best) {
          best = d[i - 2][j - 2] + 1;
        }
        d[i][j] = best;
      }
    }
    return d[a.length][b.length];
  }
}

enum _Intent { delete, restart, dnf, toRead, rate, finish, update, start }

sealed class _Resolution {
  const _Resolution();
}

final class _Title extends _Resolution {
  const _Title(this.title);

  final String title;
}

final class _Ask extends _Resolution {
  const _Ask(this.query);

  final String query;
}
