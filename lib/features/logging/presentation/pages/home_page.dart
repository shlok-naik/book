import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/ai/groq_client.dart';
import '../../../../core/purchases/plan_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/date_pill.dart';
import '../../../library/presentation/controllers/library_controller.dart';
import '../../../library/presentation/library_scope.dart';
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

/// The log page: a single command line, and a status pill under it.
///
/// The page owns the *decision* — parse the line, apply it to the
/// library, decide whether it was taken — while [CommandInput] owns how
/// that decision looks. Neither knows the other's job, which is what
/// keeps the input's "never move the text" guarantee from depending on
/// anything the page does.
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.groq});

  /// Injection point for tests: a fake wrapping fixed extractions
  /// instead of a real Groq call. Null in the app.
  final GroqClient? groq;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  /// How long the confirmation/error pill stays up before it fades out.
  static const _messageLifetime = Duration(seconds: 3);
  static const _messageFadeIn = Duration(milliseconds: 150);
  static const _messageFadeOut = Duration(milliseconds: 400);

  final _focusNode = FocusNode();
  late final GroqClient _groq = widget.groq ?? GroqClient();

  /// Only dispose a client we built ourselves — an injected one belongs
  /// to the caller.
  bool get _ownsGroq => widget.groq == null;

  String? _message;
  Timer? _messageTimer;

  /// AI-extracted commands from the reader's last submitted sentence,
  /// null whenever the plain-message pill should show instead — only
  /// ever populated on the "cactus pro" AI path, never the manual one.
  List<_Instruction>? _instructions;

  // Quick to fade in, slower to fade out — set via duration/reverseDuration
  // since AnimatedOpacity only takes one duration for both directions.
  late final _messageOpacity = AnimationController(
    vsync: this,
    duration: _messageFadeIn,
    reverseDuration: _messageFadeOut,
  );

  @override
  void dispose() {
    _focusNode.dispose();
    if (_ownsGroq) _groq.dispose();
    _messageOpacity.dispose();
    _messageTimer?.cancel();
    super.dispose();
  }

  /// Routes a submitted line to whichever mode is active — the manual
  /// parser, or (on "cactus pro") Groq's natural-language extraction.
  /// Read at submit time rather than cached, so a mid-session plan
  /// switch takes effect on the very next command.
  Future<bool> _run(String command) {
    return PlanController.isPro.value ? _runAi(command) : _runManual(command);
  }

  /// Parses [command] and applies it — the one place that decision gets
  /// made, used identically by [_runManual] (on the whole typed line)
  /// and [_runAi] (on each line Groq extracts). Every caller pops
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

  /// Runs [command] through [_runCommand] and reports it through the
  /// pill, returning whether it was taken — which is what turns into
  /// [CommandInput]'s strike-through or its shake.
  Future<bool> _runManual(String command) async {
    final result = await _runCommand(command);
    if (!mounted) return false;
    _showMessage(result.message);
    return result.success;
  }

  /// Sends a free-form sentence to Groq, then runs every line it
  /// extracts through the exact same [_runCommand] the manual path
  /// uses — each shown as its own [InstructionRow], struck through and
  /// ticked on success or shaking on failure, precisely mirroring what
  /// [CommandInput] itself does for a single typed line. A sentence
  /// with nothing recognizable in it still comes back as one line —
  /// [GroqClient]'s own prompt asks for the literal word "gibberish" in
  /// that case rather than an empty list — so that line runs through
  /// this same unrecognized-command path too instead of needing a
  /// special case here.
  ///
  /// The sentence itself only gets [CommandInput]'s strike-through once
  /// at least one extracted line actually went through — this awaits
  /// the whole run rather than accepting the moment extraction
  /// succeeds, so "the paragraph is crossed out" always means "at least
  /// one real thing happened," never just "Groq understood the words."
  /// If nothing in it succeeded, this returns false and [CommandInput]
  /// shakes the whole sentence exactly like an unrecognized manual
  /// command would.
  ///
  /// A Groq failure itself (not a line inside it — the extraction call
  /// itself) is reported through the same pill and rejects the line
  /// outright, before anything is even attempted — never a silent
  /// fallback to manual parsing, and never a retry.
  Future<bool> _runAi(String command) async {
    final List<String> commands;
    try {
      commands = await _groq.extractCommands(command);
    } on GroqException catch (error) {
      if (!mounted) return false;
      _showMessage(error.message);
      return false;
    }
    if (!mounted) return false;

    // The prompt asks Groq for a literal "gibberish" line rather than
    // an empty list when it finds nothing — this is a defensive fallback
    // for the rare reply that doesn't comply, not the normal path.
    final effectiveCommands = commands.isEmpty ? const ['gibberish'] : commands;

    setState(() {
      _message = null;
      _instructions = [
        for (final line in effectiveCommands) _Instruction(line),
      ];
    });
    return _runInstructions();
  }

  /// Runs [_instructions] one at a time, in order, each through
  /// [_runCommand] — only ever marking a line [InstructionState.done]
  /// once that has actually resolved for it, never optimistically. A
  /// failing line never stops the rest: every extracted line gets its
  /// own independent attempt, same as if the reader had submitted each
  /// on its own line in Free mode. Returns whether at least one line
  /// succeeded, which is what [_runAi] uses to decide whether the
  /// sentence itself gets crossed out.
  ///
  /// A failing line shakes in place — [InstructionRow]'s own version of
  /// [CommandInput]'s reject shake — long enough to read alongside the
  /// others before the whole list clears itself on its own, same
  /// lifetime as the confirmation pill, regardless of whether every
  /// line succeeded or some didn't.
  Future<bool> _runInstructions() async {
    final instructions = _instructions;
    if (instructions == null) return false;

    var anySucceeded = false;
    for (final instruction in instructions) {
      final result = await _runCommand(instruction.text);
      if (!mounted) return anySucceeded;
      _showMessage(result.message);

      setState(() {
        instruction.state = result.success
            ? InstructionState.done
            : InstructionState.error;
      });
      if (result.success) anySucceeded = true;

      // Lets that line's own strike/checkmark (or shake) finish reading
      // before the next line starts its own.
      await Future<void>.delayed(const Duration(milliseconds: 750));
      if (!mounted) return anySucceeded;
    }

    // Give the reader a moment with the finished list up, then clear it
    // — same lifetime as the confirmation pill, so nothing lingers on
    // screen indefinitely.
    await Future<void>.delayed(_messageLifetime);
    if (!mounted) return anySucceeded;
    setState(() => _instructions = null);
    return anySucceeded;
  }

  /// Applies a recognized command to the library, if it has one to
  /// apply — `unknown` never reaches here (the caller filters
  /// unrecognized syntax out first), so this returns null only for that
  /// impossible case, which both callers treat the same as a success.
  Future<LibraryActionResult?> _applyToLibrary(ParsedLogCommand command) {
    final title = command.title;
    if (title == null || title.isEmpty) return Future.value(null);

    final library = LibraryScope.read(context);

    switch (command.type) {
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final message = _message;
    final instructions = _instructions;

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
                  child: CommandInput(
                    focusNode: _focusNode,
                    onSubmit: _run,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 24,
                      height: 1.5,
                      color: colors.primaryText,
                    ),
                  ),
                ),
                // Both can show together: a failed instruction leaves
                // its own list up (see [_runInstructions]) at the same
                // time its pill pops underneath.
                if (instructions != null)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final instruction in instructions)
                        InstructionRow(
                          text: instruction.text,
                          state: instruction.state,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 14,
                            color: colors.primaryText,
                          ),
                        ),
                    ],
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
