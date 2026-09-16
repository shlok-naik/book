import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/ai/ai_command_parser.dart';
import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/network/connectivity_controller.dart';
import '../../../../core/purchases/plan_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../goals/presentation/goal_scope.dart';
import '../../../goals/presentation/widgets/goal_progress_view.dart';
import '../../../library/domain/collections.dart';
import '../../../library/domain/library_exception.dart';
import '../../../library/presentation/controllers/library_controller.dart';
import '../../../library/presentation/library_scope.dart';
import '../../../library/presentation/widgets/removal_confirmations.dart';
import '../../../memory/presentation/memory_scope.dart';
import '../../../search/presentation/widgets/book_picker_sheet.dart';
import '../../../shell/presentation/widgets/bottom_switcher.dart';
import '../../../shell/presentation/widgets/top_bar.dart';
import '../../../streaks/domain/reading_stats.dart';
import '../../domain/log_command_parser.dart';
import '../../domain/smart_command_parser.dart';
import '../parser_mode_controller.dart';
import '../widgets/command_input.dart';
import '../widgets/confirmation_pill.dart';
import '../widgets/currently_reading_card.dart';
import '../widgets/instruction_row.dart';
import '../widgets/reading_streak.dart';
import 'isbn_scanner_page.dart';

/// One AI-extracted command line and where it stands in its own
/// execution — see [InstructionState].
class _Instruction {
  _Instruction(this.text);

  final String text;
  InstructionState state = InstructionState.pending;
}

/// Slides a gradient sideways by a fraction of its own bounds — the
/// standard recipe for a shimmer effect, paired with a repeating
/// [LinearGradient.tileMode] so the colors sliding off one edge are
/// exactly the colors already sliding in the other.
class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform(this.slidePercent);

  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0, 0);
  }
}

/// The log page: a single command line, and a status pill under it.
///
/// The page owns the *decision* — parse the line, apply it to the
/// library, decide whether it was taken — while [CommandInput] owns how
/// that decision looks. Neither knows the other's job, which is what
/// keeps the input's "never move the text" guarantee from depending on
/// anything the page does.
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.aiParser, this.onOpenMemory});

  /// Injection point for tests: a fake wrapping fixed extractions
  /// instead of a real call to the `parse-command` edge function. Null
  /// in the app.
  final AiCommandParser? aiParser;

  /// Switches the shell to the Memory tab — what typing a bare `memory`
  /// does (see [_isOpenMemory]). Null outside `RootShell` (a test pumping
  /// this page alone), where `memory` falls through to the parser like
  /// any other unrecognized word.
  final VoidCallback? onOpenMemory;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  /// How long the confirmation/error pill stays up before it fades out.
  static const _messageLifetime = Duration(seconds: 3);
  static const _messageFadeIn = Duration(milliseconds: 150);
  static const _messageFadeOut = Duration(milliseconds: 400);

  final _focusNode = FocusNode();
  late final AiCommandParser _ai =
      widget.aiParser ?? const EdgeFunctionCommandParser();

  String? _message;
  ConfirmationTone _messageTone = ConfirmationTone.neutral;

  Timer? _messageTimer;

  /// A backed-out command is neither taken nor refused — a neutral note.
  static ConfirmationTone _toneOf(
    ({bool success, bool cancelled, String message}) result,
  ) => result.cancelled
      ? ConfirmationTone.neutral
      : result.success
      ? ConfirmationTone.success
      : ConfirmationTone.failure;

  /// Whether the on-screen keyboard is up — what decides whether the
  /// currently-reading card, the goal and the streak show (see [build]).
  /// The keyboard *replaces* them: while it's up the page is just its title
  /// and the command line above it, and once it goes down the three come
  /// back where it was.
  ///
  /// Read from the [MediaQuery] *above* this page's own [Scaffold]: a
  /// Scaffold that resizes for the keyboard hands its body a zero bottom
  /// inset, so asking from inside it would always say "no keyboard".
  static bool _keyboardVisible(BuildContext context) =>
      MediaQuery.viewInsetsOf(context).bottom > 0;

  /// AI-extracted commands from the reader's last submitted sentence,
  /// null whenever the plain-message pill should show instead — only
  /// ever populated on the "cactus pro" AI path, never the manual one.
  List<_Instruction>? _instructions;

  /// True from the moment a sentence is handed to the AI until it comes
  /// back (however that turns out) — [build] uses this to tint
  /// [CommandInput]'s still-visible typed text with [_aiGradient]
  /// while it's genuinely waiting on a response, never before or after.
  bool _aiThinking = false;

  // Quick to fade in, slower to fade out — set via duration/reverseDuration
  // since AnimatedOpacity only takes one duration for both directions.
  late final _messageOpacity = AnimationController(
    vsync: this,
    duration: _messageFadeIn,
    reverseDuration: _messageFadeOut,
  );

  /// Starts each new [_instructions] list fully visible (no fade in —
  /// the swap from the typed sentence is instant) and is only ever
  /// animated in reverse, once, right before the list is cleared.
  late final _instructionsOpacity = AnimationController(
    vsync: this,
    value: 1,
    duration: _messageFadeOut,
  );

  /// Drives [_SlidingGradientTransform] while [_aiThinking] — a quick,
  /// continuous loop (not the one-shot fades above) since "the AI is
  /// working on this" is an ongoing state, not a single transition.
  /// Only ever running while [_aiThinking] is true (see [_runAi]); an
  /// idle repeating controller costs nothing extra to leave ticking,
  /// but there's nothing to animate for it to drive when it's not.
  late final _thinkingGradient = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void initState() {
    super.initState();
    // Warms the memory list before the reader ever opens the profile
    // page, so a "recommend" on their very first cactus pro sentence
    // still has their remembered notes to ground it in — `load` is a
    // no-op if the profile page already triggered it. `read`, not `of`:
    // this doesn't need to rebuild when memories change, only to kick
    // the fetch off once.
    //
    // Deferred to the post-frame callback rather than called inline:
    // `MemoryScope` is an `InheritedNotifier` wrapping the whole app, so
    // a `notifyListeners()` fired synchronously from here — still
    // inside the very first build — would try to rebuild an ancestor
    // that is itself mid-mount. `StreaksController` sidesteps the same
    // hazard by building in `didChangeDependencies` instead of
    // `initState`; a post-frame callback is the equivalent fix for a
    // controller that lives above this widget rather than inside it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(MemoryScope.read(context).load());
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _messageOpacity.dispose();
    _instructionsOpacity.dispose();
    _thinkingGradient.dispose();
    _messageTimer?.cancel();
    super.dispose();
  }

  /// Routes a submitted line to whichever parser is active
  /// ([ParserModeController.effective]) — the manual parser, the on-device
  /// beta parser, or (on "cactus pro") the AI's natural-language
  /// extraction. Read at submit time rather than cached, so a mid-session
  /// plan or debug switch takes effect on the very next command.
  Future<CommandOutcome> _run(String command) {
    if (_isOpenMemory(command)) return Future.value(_openMemory());
    // Offline, the AI path can't run at all (it's an edge function), so a
    // pro reader's line goes to the manual parser instead — a typed command
    // still saves offline, where a sentence would only fail.
    return switch (ParserModeController.effective(
      offline: ConnectivityController.isOffline.value,
    )) {
      ParserMode.proAi => _runAi(command),
      ParserMode.beta => _runSmart(command),
      ParserMode.classic => _runManual(command),
    };
  }

  /// The beta parser: [SmartCommandParser] turns a sentence into command
  /// lines on the device, asking with the book picker for any action whose
  /// book is missing or unclear — then the lines run exactly as the AI's
  /// do ([_showInstructions]). A line that was already a command, unchanged,
  /// runs as a plain manual command.
  Future<CommandOutcome> _runSmart(String command) async {
    final library = LibraryScope.read(context);
    final lines = SmartCommandParser.parse(
      command,
      library: [
        for (final entry in library.books)
          SmartBook(
            title: entry.book.title,
            author: entry.book.author,
            isReading: entry.isReading,
          ),
      ],
      today: DateTime.now(),
    );
    if (lines.isEmpty) return _runManual(command);

    final commands = <String>[];
    for (final line in lines) {
      switch (line) {
        case ResolvedLine(command: final resolved):
          commands.add(resolved);
        case UnrecognizedLine(:final text):
          commands.add(text);
        case NeedsBookLine():
          final title = await _askForBook(line);
          if (!mounted) return CommandOutcome.rejected;
          if (title != null) commands.add(line.commandFor(title));
      }
    }

    if (commands.isEmpty) {
      _showMessage('Kept looking', ConfirmationTone.neutral);
      return CommandOutcome.dismissed;
    }
    if (commands.length == 1 && commands.single == command.trim()) {
      return _runManual(command);
    }
    _showInstructions(commands);
    return CommandOutcome.accepted;
  }

  /// Which book an action meant, from the book picker: a shelf book's own
  /// title, or a Google Books volume cached first so the command that runs
  /// next finds exactly that book. Null when the reader backs out.
  Future<String?> _askForBook(NeedsBookLine line) async {
    final query = line.query;
    final pick = await showBookPicker(
      context,
      query: query,
      prompt: query.isEmpty ? 'which book?' : 'which "$query"?',
    );
    if (!mounted) return null;
    _focusNode.requestFocus();
    switch (pick) {
      case null:
        return null;
      case ShelfPick(:final entry):
        return entry.book.title;
      case CataloguePick(:final volume):
        try {
          final book = await LibraryScope.read(
            context,
          ).lookup.resolveVolume(volume);
          return book.title;
        } on LibraryException catch (error) {
          if (mounted) _showMessage(error.message, ConfirmationTone.failure);
          return null;
        }
    }
  }

  /// A bare `memory` (any case, surrounding space ignored) is a way to the
  /// Memory tab, not a command — checked before either parser, the same
  /// way `start isbn` is recognized ahead of the grammar. Both plans get
  /// it: on the free plan the tab shows its locked preview, which is the
  /// point — a reader who guesses the word learns what it unlocks.
  bool _isOpenMemory(String command) =>
      widget.onOpenMemory != null && command.trim().toLowerCase() == 'memory';

  /// Opens the tab and clears the field without re-focusing it (see
  /// [CommandOutcome.handled]). No pill: the tab switching under the
  /// reader's thumb already says it worked.
  CommandOutcome _openMemory() {
    AppHaptics.selection();
    _focusNode.unfocus();
    widget.onOpenMemory!();
    return CommandOutcome.handled;
  }

  /// Parses [command] and applies it — the one place that decision gets
  /// made, used identically by [_runManual] (on the whole typed line)
  /// and [_runAi] (on each line the AI extracts). Every caller pops
  /// [message] into the same pill regardless of which of the two ways a
  /// line can be refused it hit: syntax the parser doesn't recognize,
  /// or syntax it does recognize but that the library rejects (offline,
  /// a book already on the shelf, a page past the end).
  ///
  /// Never throws: anything unexpected underneath (a parser or repository
  /// bug) comes back as a failed line with a message. Without that, a throw
  /// would leave an AI instruction list on screen forever — the command
  /// field only returns once every line has had its turn.
  Future<({bool success, bool cancelled, String message})> _runCommand(
    String command,
  ) async {
    try {
      return await _parseAndApply(command);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'HomePage',
        'A command failed unexpectedly.',
        error: error,
        stackTrace: stackTrace,
      );
      return (success: false, cancelled: false, message: "That didn't work.");
    }
  }

  Future<({bool success, bool cancelled, String message})> _parseAndApply(
    String command,
  ) async {
    final parsed = LogCommandParser.parse(command);
    if (!parsed.recognized) {
      return (success: false, cancelled: false, message: parsed.message);
    }

    final outcome = await _applyToLibrary(parsed);
    if (outcome != null && !outcome.success) {
      return (
        success: false,
        cancelled: outcome.cancelled,
        message: outcome.message ?? 'Something went wrong.',
      );
    }
    // The parser's own optimistic message is the pill text for every
    // command — except the ones it couldn't name a book for (an unquoted
    // `add comment` or `move`, and the `make` family), where only the
    // library's result knows which book, shelf or stored name it was; and
    // every `move`, where only the library knows whether the book was added
    // or moved, and what the shelf is really called.
    //
    // Also every `remove` (only the library knows what was removed from
    // where), and any command whose book wasn't on the shelf and was added
    // first — the parser's "Finished Dune" can't say it was added.
    final libraryMessage = outcome?.message;
    final preferLibrary =
        parsed.title == null ||
        parsed.type == LogCommandType.move ||
        _isRemoval(parsed.type) ||
        (outcome?.addedToLibrary ?? false);
    return (
      success: true,
      cancelled: false,
      message: preferLibrary && libraryMessage != null
          ? libraryMessage
          : parsed.message,
    );
  }

  /// The one place a command's outcome turns into a haptic — both the
  /// manual path and each AI-extracted line come through here, so the
  /// feel of "taken" and "refused" is identical either way. Fired at the
  /// moment the outcome is known, alongside the pill and the
  /// strike-through, rather than at submit: a haptic that arrives before
  /// the answer is just noise.
  void _feedback({required bool success}) {
    if (success) {
      AppHaptics.accepted();
    } else {
      AppHaptics.rejected();
    }
  }

  /// Runs [command] through [_runCommand] and reports it through the
  /// pill, returning whether it was taken — which is what turns into
  /// [CommandInput]'s strike-through or its shake.
  Future<CommandOutcome> _runManual(String command) async {
    final result = await _runCommand(command);
    if (!mounted) return CommandOutcome.rejected;
    if (!result.cancelled) _feedback(success: result.success);
    _showMessage(result.message, _toneOf(result));
    if (result.cancelled) return CommandOutcome.dismissed;
    return result.success ? CommandOutcome.accepted : CommandOutcome.rejected;
  }

  /// Sends a free-form sentence to the AI and, once it comes back, swaps
  /// the typed sentence out for the extracted lines themselves —
  /// [build] renders [_instructions] in the exact spot and exact style
  /// [CommandInput] occupied, so the paragraph reads as if it just
  /// turned into those commands rather than sitting alongside them. A
  /// sentence with nothing recognizable in it still comes back as one
  /// line — the edge function's own prompt asks for the literal word
  /// "gibberish" in that case rather than an empty list — so that line
  /// goes through the same swap and the same unrecognized-command path
  /// as any other, instead of needing a special case here.
  ///
  /// Fires [_runInstructions] without waiting on it: by the time this
  /// returns, [CommandInput] has already been replaced (see [build]),
  /// so there's nothing left for its own accept/shake to apply to —
  /// running the lines is now entirely [_instructions]' and
  /// [InstructionRow]'s job.
  ///
  /// An AI failure itself (not a line inside it — the extraction call
  /// itself) is reported through the same pill and rejects the line
  /// outright, before anything is even attempted — [CommandInput] is
  /// still there to shake in that case, never a silent fallback to
  /// manual parsing, and never a retry.
  Future<CommandOutcome> _runAi(String command) async {
    setState(() => _aiThinking = true);
    _thinkingGradient.repeat();
    final library = LibraryScope.read(context);
    final memory = MemoryScope.read(context);
    final List<String> commands;
    try {
      commands = await _ai.extractCommands(
        command,
        // Grounds "recommend" only — every other command ignores this
        // (see AiCommandParser.extractCommands) — so there's no reason
        // to gate building it behind whether the sentence looks like a
        // recommend request; it's cheap and the edge function itself
        // decides whether to use it.
        libraryTitles: [
          // Every book being read or finished, whichever shelf it sits on.
          for (final book in library.books)
            if (book.isReading || book.isFinished) book.book.title,
        ],
        memoryNotes: [
          for (final entry in memory.memories)
            (title: entry.bookTitle, note: entry.note),
        ],
      );
    } on Object catch (error, stackTrace) {
      // Anything but an [AiCommandException] is a bug below — still stop
      // the shimmer and give the field back rather than thinking forever.
      if (error is! AiCommandException) {
        AppLogger.error(
          'HomePage',
          'The AI parser threw unexpectedly.',
          error: error,
          stackTrace: stackTrace,
        );
      }
      _thinkingGradient.stop();
      if (!mounted) return CommandOutcome.rejected;
      setState(() => _aiThinking = false);
      _showMessage(
        error is AiCommandException ? error.message : "Couldn't reach the AI.",
        ConfirmationTone.failure,
      );
      return CommandOutcome.rejected;
    }
    _thinkingGradient.stop();
    if (!mounted) return CommandOutcome.rejected;

    // The prompt asks for a literal "gibberish" line rather than
    // an empty list when it finds nothing — this is a defensive fallback
    // for the rare reply that doesn't comply, not the normal path.
    setState(() => _aiThinking = false);
    _showInstructions(commands.isEmpty ? const ['gibberish'] : commands);
    return CommandOutcome.accepted;
  }

  /// Swaps the typed sentence for [commands] and runs them in order — see
  /// [_runAi] and [_runInstructions].
  void _showInstructions(List<String> commands) {
    _instructionsOpacity.value = 1;
    setState(() {
      _message = null;
      _instructions = [for (final line in commands) _Instruction(line)];
    });
    unawaited(_runInstructions());
  }

  /// Runs [_instructions] one at a time, in order, each through
  /// [_runCommand] — only ever marking a line [InstructionState.done]
  /// once that has actually resolved for it, never optimistically. A
  /// failing line never permanently stops the rest — every extracted
  /// line still gets its own independent attempt, same as if the
  /// reader had submitted each on its own line in Free mode — but it
  /// does pause the sequence on its own pill for a full read (see the
  /// success/failure branch below) before the next line gets its turn,
  /// since a success' checkmark reads at a glance but a failure is the
  /// one thing here worth actually stopping to read.
  ///
  /// A failing line also shakes in place — [InstructionRow]'s own
  /// version of [CommandInput]'s reject shake. The whole list clears
  /// itself on its own once every line has had its turn, same lifetime
  /// as the confirmation pill, regardless of whether every line
  /// succeeded or some didn't. Clearing [_instructions] is what brings
  /// a fresh, empty [CommandInput] back (see [build]).
  Future<void> _runInstructions() async {
    final instructions = _instructions;
    if (instructions == null) return;

    for (final instruction in instructions) {
      final result = await _runCommand(instruction.text);
      if (!mounted) return;
      if (!result.cancelled) _feedback(success: result.success);
      _showMessage(result.message, _toneOf(result));

      setState(() {
        instruction.state = result.success
            ? InstructionState.done
            : InstructionState.error;
      });

      // A success just needs its strike/checkmark read before the next
      // line starts. A failure pauses the whole sequence for the
      // pill's own full lifetime instead — the error is the one thing
      // here worth stopping to actually read, not just glimpse before
      // it's replaced.
      await Future<void>.delayed(
        result.success || result.cancelled
            ? const Duration(milliseconds: 750)
            : _messageLifetime,
      );
      if (!mounted) return;
    }

    // Give the reader a moment with the finished list up, then fade it
    // out — same lifetime as the confirmation pill, so nothing lingers
    // on screen indefinitely, and the same fade the pill itself uses
    // rather than an abrupt disappearance.
    await Future<void>.delayed(_messageLifetime);
    if (!mounted) return;
    await _instructionsOpacity.reverse();
    if (!mounted) return;
    setState(() => _instructions = null);
  }

  static bool _isRemoval(LogCommandType type) => switch (type) {
    LogCommandType.removeShelf ||
    LogCommandType.removeTag ||
    LogCommandType.removeSeries ||
    LogCommandType.removeComment => true,
    _ => false,
  };

  /// `remove shelf|tag|series …` — resolves what the line means against the
  /// collections that exist, asks first when it would unmake the whole
  /// collection, then applies it. Backing out is a cancel, like `delete`.
  Future<LibraryActionResult> _removeCollection(
    LibraryController library,
    ParsedLogCommand command,
    CollectionKind kind,
  ) async {
    final resolved = library.resolveRemoval(
      kind,
      name: switch (kind) {
        CollectionKind.shelves => command.shelf,
        CollectionKind.tags => command.tag,
        CollectionKind.series => command.series,
      },
      title: command.title,
      argument: command.argument,
    );
    final removal = resolved.removal;
    if (removal == null) {
      return LibraryActionResult.failure(resolved.failure);
    }
    if (removal is UnmakeCollection) {
      final confirmed = await confirmUnmake(context, removal);
      if (!mounted) return const LibraryActionResult.cancelled(null);
      if (!confirmed) {
        return LibraryActionResult.cancelled('Kept "${removal.name}"');
      }
    }
    return library.applyRemoval(removal);
  }

  /// `remove comment [comment] <book>` — finds the comment, shows it, and
  /// only removes it once confirmed.
  Future<LibraryActionResult> _removeComment(
    LibraryController library,
    ParsedLogCommand command,
  ) async {
    final resolved = await library.resolveCommentRemoval(
      title: command.title,
      text: command.note,
      argument: command.argument,
    );
    final entry = resolved.entry;
    final comment = resolved.comment;
    if (!mounted) return const LibraryActionResult.cancelled(null);
    if (entry == null || comment == null) {
      return LibraryActionResult.failure(resolved.failure);
    }
    final confirmed = await confirmRemoveComment(context, entry, comment);
    if (!mounted) return const LibraryActionResult.cancelled(null);
    if (!confirmed) {
      return const LibraryActionResult.cancelled('Kept the comment');
    }
    return library.deleteComment(entry, comment);
  }

  /// Applies a recognized command — to the shelf for the original five,
  /// to the memory list for `remember`, or not at all for `recommend`
  /// (the AI has already resolved a title and reason by the time this
  /// runs; there's nothing left to persist) — if it has one to apply.
  /// `unknown` never reaches here (the caller filters unrecognized
  /// syntax out first), so this returns null only for that impossible
  /// case, which both callers treat the same as a success.
  ///
  /// `remember`/`recommend` are gated on [PlanController.isPro] here
  /// rather than in `LogCommandParser`, so the syntax check and the
  /// plan check stay two separate concerns — the same reasoning
  /// `_run`'s own free/pro branch already follows.
  Future<LibraryActionResult?> _applyToLibrary(ParsedLogCommand command) {
    final library = LibraryScope.read(context);

    // An unquoted `add comment` is the one recognized command that has no
    // title yet — the library has to find where the comment ends and the
    // book begins. Handled before the title check below, which would
    // otherwise wave it through as a silent success.
    if (command.type == LogCommandType.addComment && command.title == null) {
      final note = command.note;
      if (note == null || note.isEmpty) {
        return Future.value(
          const LibraryActionResult.failure('That comment was empty.'),
        );
      }
      return library.addComment(note);
    }

    if (command.type == LogCommandType.startIsbn) {
      return _startByIsbnScan(library, loggedAt: command.date);
    }

    // An unquoted `move` has no title either — only the shelves that exist
    // can say where the title ends and the shelf name begins.
    if (command.type == LogCommandType.move && command.title == null) {
      final argument = command.argument;
      if (argument == null || argument.isEmpty) {
        return Future.value(
          const LibraryActionResult.failure('Name a book and a shelf.'),
        );
      }
      return library.moveToShelfUnsplit(argument);
    }

    // The `make` and `remove` families may name no book at all, so they are
    // routed before the title check. Each goes to the same function the
    // library page's "+" panel uses.
    switch (command.type) {
      case LogCommandType.removeShelf:
        return _removeCollection(library, command, CollectionKind.shelves);
      case LogCommandType.removeTag:
        return _removeCollection(library, command, CollectionKind.tags);
      case LogCommandType.removeSeries:
        return _removeCollection(library, command, CollectionKind.series);
      case LogCommandType.removeComment:
        return _removeComment(library, command);
      case LogCommandType.makeShelf:
        return library.makeShelf(
          command.shelf ?? '',
          isPro: PlanController.isPro.value,
        );
      case LogCommandType.makeTag:
        return library.makeTag(
          command.tag ?? '',
          isPro: PlanController.isPro.value,
        );
      case LogCommandType.makeSeries:
        return library.makeSeries(
          command.series ?? '',
          isPro: PlanController.isPro.value,
        );
      default:
        break;
    }

    final title = command.title;
    if (title == null || title.isEmpty) return Future.value(null);

    switch (command.type) {
      case LogCommandType.remember:
        if (!PlanController.isPro.value) {
          return Future.value(
            const LibraryActionResult.failure('Memories need cactus pro.'),
          );
        }
        final note = command.note;
        if (note == null || note.isEmpty) {
          return Future.value(
            const LibraryActionResult.failure('Memory is empty.'),
          );
        }
        return MemoryScope.read(context)
            .remember(bookTitle: title, note: note)
            .then(
              (result) => result.success
                  ? LibraryActionResult.success(result.message)
                  : LibraryActionResult.failure(result.message),
            );
      case LogCommandType.recommend:
        return Future.value(
          PlanController.isPro.value
              ? const LibraryActionResult.success()
              : const LibraryActionResult.failure(
                  'Recommendations need cactus pro.',
                ),
        );
      case LogCommandType.start:
        return library.startBook(title, loggedAt: command.date);
      case LogCommandType.update:
        final percent = command.percent;
        if (percent != null) {
          return library.updateProgressByPercent(
            title,
            percent,
            loggedAt: command.date,
          );
        }
        final page = command.page;
        if (page == null) {
          return Future.value(
            const LibraryActionResult.failure('Invalid page number.'),
          );
        }
        return library.updateProgress(title, page, loggedAt: command.date);
      case LogCommandType.finish:
        return library.finishBook(title, loggedAt: command.date);
      case LogCommandType.restart:
        return library.restartBook(title, loggedAt: command.date);
      case LogCommandType.delete:
        return _confirmDelete(library, title);
      case LogCommandType.move:
        // Only the quoted form gets here — an unquoted move has no title
        // and was routed at the top of this method.
        final shelf = command.shelf;
        if (shelf == null || shelf.isEmpty) {
          return Future.value(
            const LibraryActionResult.failure('Name a shelf.'),
          );
        }
        return library.moveToShelf(title, shelf);
      case LogCommandType.addTag:
        final tag = command.tag;
        if (tag == null || tag.isEmpty) {
          return Future.value(
            const LibraryActionResult.failure('Name the tag.'),
          );
        }
        return library.addTag(title, tag);
      case LogCommandType.addComment:
        // Only the quoted form gets here — an unquoted comment has no
        // title and was routed at the top of this method.
        return library.addComment(command.note ?? '', title: title);
      case LogCommandType.addSeries:
        final name = command.series;
        if (name == null || name.isEmpty) {
          return Future.value(
            const LibraryActionResult.failure('Name the series first.'),
          );
        }
        return library.addToSeries(
          title,
          name,
          position: command.seriesPosition,
        );
      case LogCommandType.startIsbn:
      case LogCommandType.makeShelf:
      case LogCommandType.makeTag:
      case LogCommandType.makeSeries:
      case LogCommandType.removeShelf:
      case LogCommandType.removeTag:
      case LogCommandType.removeSeries:
      case LogCommandType.removeComment:
        // Handled above, before the title check — never reached.
        return Future.value(null);
      case LogCommandType.rate:
        final rating = command.rating;
        if (rating == null) {
          return Future.value(
            const LibraryActionResult.failure('Invalid rating.'),
          );
        }
        return library.rateBook(title, rating);
      case LogCommandType.unknown:
        return Future.value(null);
    }
  }

  /// `start isbn` — opens the camera and, once it scans a barcode, starts
  /// whatever book that ISBN resolves to. Backing out of the camera
  /// (the header's back chevron) is a cancel, not a failure, same as
  /// backing out of the delete confirmation above.
  Future<LibraryActionResult> _startByIsbnScan(
    LibraryController library, {
    DateTime? loggedAt,
  }) async {
    final isbn = await scanIsbn(context);
    if (!mounted) return const LibraryActionResult.cancelled(null);
    if (isbn == null) {
      return const LibraryActionResult.cancelled('Kept looking');
    }
    return library.startBookByIsbn(isbn, loggedAt: loggedAt);
  }

  /// `delete` asks first: it takes the book's tags, comments and journal
  /// history with it, and nothing brings those back. A title that matches
  /// nothing skips the question and lets the library report that.
  Future<LibraryActionResult> _confirmDelete(
    LibraryController library,
    String title,
  ) async {
    final entry = library.match(title);
    if (entry == null) return library.deleteBook(title);

    final confirmed = await confirmRemoveBook(context, entry);
    if (!confirmed) {
      return LibraryActionResult.cancelled('Kept "${entry.book.title}"');
    }
    // By id: exactly the book the dialog named, even if another book shares
    // its title or the shelf changed while the dialog was up.
    return library.deleteBookById(entry.id);
  }

  /// Puts [message] in the pill and (re)starts its fade-in / lifetime /
  /// fade-out cycle.
  void _showMessage(
    String message, [
    ConfirmationTone tone = ConfirmationTone.neutral,
  ]) {
    setState(() {
      _message = message;
      _messageTone = tone;
    });
    _messageOpacity.forward(from: 0);
    _messageTimer?.cancel();
    _messageTimer = Timer(_messageLifetime, () async {
      if (!mounted) return;
      await _messageOpacity.reverse();
      // Only clear if nothing new arrived during the fade.
      if (mounted && _messageOpacity.isDismissed) {
        setState(() => _message = null);
      }
    });
  }

  /// The one type style shared by [CommandInput] and, once the AI's
  /// extracted lines replace it, every [InstructionRow] — so a command
  /// reads exactly like it was typed there itself, just swapped in
  /// rather than edited into.
  TextStyle _inputStyle(AppColors colors) {
    return context.fonts.interface(
      fontSize: 16,
      height: 1.5,
      color: colors.primaryText,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final message = _message;
    final instructions = _instructions;
    // Reactive: rebuilds this page the moment a shelf command changes
    // which book is most recently active, same as any other LibraryScope
    // read in a build method.
    // The most recently *active* reading book, not the top of the reading
    // section — the reader may have dragged that one there by hand.
    final library = LibraryScope.of(context);
    final currentBook = library.currentlyReading;
    final goals = GoalScope.of(context);
    final showPeek = !_keyboardVisible(context);

    Widget commandInput = CommandInput(
      focusNode: _focusNode,
      onSubmit: _run,
      style: _inputStyle(colors),
    );
    if (_aiThinking) {
      // A sliding, mirror-tiled version of [aiGradient] — same colors
      // [InstructionRow] uses for the generated commands below, just
      // in motion while there's nothing generated yet to look at.
      commandInput = AnimatedBuilder(
        animation: _thinkingGradient,
        child: commandInput,
        builder: (context, child) => ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            colors: aiGradient.colors,
            tileMode: TileMode.mirror,
            transform: _SlidingGradientTransform(_thinkingGradient.value),
          ).createShader(bounds),
          child: child,
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _focusNode.requestFocus,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.xl,
              // The streak sits just clear of the floating bar.
              BottomSwitcher.pageFootprint + AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Same AppSpacing.md top inset as library/streak/memory
                // — without it "add" sat lower than the title on every
                // other tab despite sharing the exact same TopBar.
                const TopBar(title: 'add'),
                const SizedBox(height: AppSpacing.lg),
                Expanded(
                  // The field stays mounted (and focused) under the
                  // instruction list, so running a sentence's commands
                  // never drops the keyboard.
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Visibility(
                        visible: instructions == null,
                        maintainState: true,
                        maintainAnimation: true,
                        child: commandInput,
                      ),
                      if (instructions != null)
                        FadeTransition(
                          opacity: _instructionsOpacity,
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final instruction in instructions)
                                  InstructionRow(
                                    text: instruction.text,
                                    state: instruction.state,
                                    style: _inputStyle(colors),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                FadeTransition(
                  opacity: _messageOpacity,
                  child: message != null
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ConfirmationPill(
                              message: message,
                              tone: _messageTone,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
                // The currently-reading row, the goal and the streak
                // readout, stacked just above the floating bottom bar.
                // Hidden while the keyboard is up — it takes their place,
                // see [_keyboardVisible] — and back once it's down. A
                // hairline (not a box — see both widgets' own doc
                // comments on why this app doesn't use card chrome) is
                // what keeps them legible as separate things now that
                // none has a fill of its own to do that.
                if (showPeek) ...[
                  if (currentBook != null)
                    CurrentlyReadingCard(entry: currentBook)
                  else
                    // Same copy the streak journal's own empty state
                    // uses for "nothing to show here yet" — one phrase
                    // for the one situation, not two different ways of
                    // saying it depending which screen you're on.
                    Text(
                      'nothing logged yet — start a book.',
                      style: context.fonts.interface(
                        fontSize: 13,
                        color: colors.secondaryText,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  Divider(height: 1, thickness: 1, color: colors.divider),
                  const SizedBox(height: AppSpacing.md),
                  // The yearly goal sits between the book and the streak:
                  // hidden until it has loaded, so a reader who has one
                  // never sees a "set a goal" prompt flash first.
                  if (goals.isLoaded) ...[
                    GoalProgressView(
                      compact: true,
                      editable: false,
                      progress: ReadingStats.forShelf(
                        library.books,
                        importedAt: library.importedAt,
                      ).goalProgress(goals.goal),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Divider(height: 1, thickness: 1, color: colors.divider),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ],
                // Visibility, not a conditional in the list above: an
                // `if` that removes this from the tree would unmount
                // ReadingStreak's State every time the keyboard rises,
                // losing its already-loaded streak and forcing a fresh
                // Supabase fetch (with a flash of nothing while it
                // reloads) every single time it goes back down.
                // `maintainState: true` keeps it alive and loaded the
                // whole session through, exactly like the streak/memory
                // pages' own controllers do.
                Visibility(
                  visible: showPeek,
                  maintainState: true,
                  maintainAnimation: true,
                  child: const ReadingStreak(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
