import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/date_pill.dart';
import '../../../library/presentation/controllers/library_controller.dart';
import '../../../library/presentation/library_scope.dart';
import '../../domain/log_command_parser.dart';
import '../widgets/command_input.dart';
import '../widgets/confirmation_pill.dart';

/// The log page: a single command line, and a status pill under it.
///
/// The page owns the *decision* — parse the line, apply it to the
/// library, decide whether it was taken — while [CommandInput] owns how
/// that decision looks. Neither knows the other's job, which is what
/// keeps the input's "never move the text" guarantee from depending on
/// anything the page does.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  /// How long the confirmation/error pill stays up before it fades out.
  static const _messageLifetime = Duration(seconds: 3);
  static const _messageFadeIn = Duration(milliseconds: 150);
  static const _messageFadeOut = Duration(milliseconds: 400);

  final _focusNode = FocusNode();

  String? _message;
  Timer? _messageTimer;

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
    _messageOpacity.dispose();
    _messageTimer?.cancel();
    super.dispose();
  }

  /// Parses a submitted line and applies it, returning whether it was
  /// taken — which is what turns into the strike-through or the shake.
  ///
  /// Two ways a line can be refused, both reported the same way to the
  /// reader: syntax the parser doesn't recognize, and syntax it does
  /// recognize but that the library rejects (offline, a book already on
  /// the shelf, a page past the end). Either way the pill explains it
  /// and the text stays in the field to be corrected.
  Future<bool> _run(String command) async {
    final parsed = LogCommandParser.parse(command);
    if (!parsed.recognized) {
      _showMessage(parsed.message);
      return false;
    }

    final outcome = await _applyToLibrary(parsed);
    if (!mounted) return false;

    if (outcome != null && !outcome.success) {
      _showMessage(outcome.message ?? 'Something went wrong.');
      return false;
    }

    _showMessage(parsed.message);
    return true;
  }

  /// Applies a recognized command to the library, if it has one to
  /// apply — `unknown` never reaches here (the caller filters
  /// unrecognized syntax out first), so this returns null only for that
  /// impossible case, which [_run] treats the same as a success.
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
