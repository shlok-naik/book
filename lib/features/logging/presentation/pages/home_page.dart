import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/ai/ai_command_parser.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/purchases/plan_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/date_pill.dart';
import '../../../library/presentation/controllers/library_controller.dart';
import '../../../library/presentation/library_scope.dart';
import '../../../memory/presentation/memory_scope.dart';
import '../../domain/log_command_parser.dart';
import '../widgets/command_input.dart';
import '../widgets/confirmation_pill.dart';
import '../widgets/instruction_row.dart';

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
  const HomePage({super.key, this.aiParser});

  /// Injection point for tests: a fake wrapping fixed extractions
  /// instead of a real call to the `parse-command` edge function. Null
  /// in the app.
  final AiCommandParser? aiParser;

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
  Timer? _messageTimer;

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

  /// Routes a submitted line to whichever mode is active — the manual
  /// parser, or (on "cactus pro") the AI's natural-language extraction.
  /// Read at submit time rather than cached, so a mid-session plan
  /// switch takes effect on the very next command.
  Future<bool> _run(String command) {
    return PlanController.isPro.value ? _runAi(command) : _runManual(command);
  }

  /// Parses [command] and applies it — the one place that decision gets
  /// made, used identically by [_runManual] (on the whole typed line)
  /// and [_runAi] (on each line the AI extracts). Every caller pops
  /// [message] into the same pill regardless of which of the two ways a
  /// line can be refused it hit: syntax the parser doesn't recognize,
  /// or syntax it does recognize but that the library rejects (offline,
  /// a book already on the shelf, a page past the end).
  Future<({bool success, String message})> _runCommand(String command) async {
    final parsed = LogCommandParser.parse(command);
    if (!parsed.recognized) {
      return (success: false, message: parsed.message);
    }

    final outcome = await _applyToLibrary(parsed);
    if (outcome != null && !outcome.success) {
      return (
        success: false,
        message: outcome.message ?? 'Something went wrong.',
      );
    }
    return (success: true, message: parsed.message);
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
  Future<bool> _runManual(String command) async {
    final result = await _runCommand(command);
    if (!mounted) return false;
    _feedback(success: result.success);
    _showMessage(result.message);
    return result.success;
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
  Future<bool> _runAi(String command) async {
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
          for (final book in [...library.inProgress, ...library.finished])
            book.book.title,
        ],
        memoryNotes: [
          for (final entry in memory.memories)
            (title: entry.bookTitle, note: entry.note),
        ],
      );
    } on AiCommandException catch (error) {
      _thinkingGradient.stop();
      if (!mounted) return false;
      setState(() => _aiThinking = false);
      _showMessage(error.message);
      return false;
    }
    _thinkingGradient.stop();
    if (!mounted) return false;

    // The prompt asks for a literal "gibberish" line rather than
    // an empty list when it finds nothing — this is a defensive fallback
    // for the rare reply that doesn't comply, not the normal path.
    final effectiveCommands = commands.isEmpty ? const ['gibberish'] : commands;

    _instructionsOpacity.value = 1;
    setState(() {
      _aiThinking = false;
      _message = null;
      _instructions = [
        for (final line in effectiveCommands) _Instruction(line),
      ];
    });
    unawaited(_runInstructions());
    return true;
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
      _feedback(success: result.success);
      _showMessage(result.message);

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
        result.success ? const Duration(milliseconds: 750) : _messageLifetime,
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
    final title = command.title;
    if (title == null || title.isEmpty) return Future.value(null);

    final library = LibraryScope.read(context);

    switch (command.type) {
      case LogCommandType.remember:
        if (!PlanController.isPro.value) {
          return Future.value(
            const LibraryActionResult.failure(
              'Upgrade to cactus pro to save memories.',
            ),
          );
        }
        final note = command.note;
        if (note == null || note.isEmpty) {
          return Future.value(
            const LibraryActionResult.failure(
              "That memory didn't have a note to save.",
            ),
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
                  'Upgrade to cactus pro for recommendations.',
                ),
        );
      case LogCommandType.start:
        return library.startBook(title);
      case LogCommandType.update:
        final page = command.page;
        if (page == null) {
          return Future.value(
            const LibraryActionResult.failure(
              "That page number isn't a number we can use.",
            ),
          );
        }
        return library.updateProgress(title, page);
      case LogCommandType.finish:
        return library.finishBook(title);
      case LogCommandType.delete:
        return library.deleteBook(title);
      case LogCommandType.rate:
        final rating = command.rating;
        if (rating == null) {
          return Future.value(
            const LibraryActionResult.failure(
              "That rating isn't a number we can use.",
            ),
          );
        }
        return library.rateBook(title, rating);
      case LogCommandType.unknown:
        return Future.value(null);
    }
  }

  /// Puts [message] in the pill and (re)starts its fade-in / lifetime /
  /// fade-out cycle.
  void _showMessage(String message) {
    setState(() => _message = message);
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
    return GoogleFonts.jetBrainsMono(
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
              AppSpacing.xxl,
              AppSpacing.xl,
              130,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: DatePill()),
                const SizedBox(height: AppSpacing.lg),
                Expanded(
                  child: instructions == null
                      ? commandInput
                      : FadeTransition(
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
                ),
                FadeTransition(
                  opacity: _messageOpacity,
                  child: message != null
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ConfirmationPill(message: message),
                            const SizedBox(height: AppSpacing.xs),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
