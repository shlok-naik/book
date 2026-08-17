import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/date_pill.dart';
import '../../../library/presentation/controllers/library_controller.dart';
import '../../../library/presentation/library_scope.dart';
import '../../domain/log_command_parser.dart';
import '../widgets/completed_command.dart';
import '../widgets/confirmation_pill.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  /// Locked height for the input row so swapping between the text field,
  /// the completed state, and the shake never nudges the layout size.
  static const _inputAreaHeight = 48.0;

  /// How long the confirmation/error pill stays up before it fades out.
  static const _messageLifetime = Duration(seconds: 3);
  static const _messageFadeIn = Duration(milliseconds: 150);
  static const _messageFadeOut = Duration(milliseconds: 400);

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  ParsedLogCommand? _lastResult;
  String? _completedText;
  Timer? _messageTimer;

  late final _strikeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  late final _shakeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );
  // Quick to fade in, slower to fade out — set via duration/reverseDuration
  // since AnimatedOpacity only takes one duration for both directions.
  late final _messageOpacity = AnimationController(
    vsync: this,
    duration: _messageFadeIn,
    reverseDuration: _messageFadeOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _strikeController.dispose();
    _shakeController.dispose();
    _messageOpacity.dispose();
    _messageTimer?.cancel();
    super.dispose();
  }

  /// Handles a submitted line.
  ///
  /// Unrecognized syntax rejects immediately. Recognized syntax still
  /// has to clear the library — Supabase, Google Books, a duplicate
  /// `start`, a page past the end — before it's actually a success, so
  /// this waits for [_applyToLibrary] and only plays the
  /// strike-through/checkmark once that's confirmed. A command that
  /// looked valid but didn't apply gets the same shake and stays in the
  /// field as one that was never recognized, so nothing that silently
  /// failed can look like it went through.
  Future<void> _confirm(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;

    final parsed = LogCommandParser.parse(trimmed);
    if (!parsed.recognized) {
      _reject(parsed);
      return;
    }

    final outcome = await _applyToLibrary(parsed);
    if (!mounted) return;
    if (outcome != null && !outcome.success) {
      _reject(
        ParsedLogCommand(
          message: outcome.message ?? 'Something went wrong.',
          recognized: false,
        ),
      );
      return;
    }

    _showResult(parsed);
    setState(() => _completedText = trimmed);
    _controller.clear();
    _strikeController.forward(from: 0);

    await Future.delayed(const Duration(milliseconds: 1300));
    if (!mounted) return;
    setState(() => _completedText = null);
    _focusNode.requestFocus();
  }

  /// Shows [result] in the pill and shakes the input, leaving the typed
  /// text in place — for syntax the parser never recognized, and for
  /// syntax it did but that failed to apply.
  void _reject(ParsedLogCommand result) {
    _showResult(result);
    _shakeController.forward(from: 0);
  }

  /// Puts [result] in the confirmation pill and (re)starts its
  /// fade-in/lifetime/fade-out cycle.
  void _showResult(ParsedLogCommand result) {
    setState(() => _lastResult = result);
    _messageOpacity.forward(from: 0);
    _messageTimer?.cancel();
    _messageTimer = Timer(_messageLifetime, () async {
      if (!mounted) return;
      await _messageOpacity.reverse();
      // Only clear if nothing new arrived during the fade.
      if (mounted && _messageOpacity.isDismissed) {
        setState(() => _lastResult = null);
      }
    });
  }

  /// Applies a recognized command to the library, if it has one to
  /// apply — `rate` doesn't (ratings are out of scope for the library
  /// feature; the parser's own confirmation is the whole of it), so this
  /// returns null and [_confirm] treats that the same as a success.
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
      case LogCommandType.unknown:
        return Future.value(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final inputStyle = GoogleFonts.jetBrainsMono(
      fontSize: 24,
      height: 1.5,
      color: colors.primaryText,
    );
    final completedText = _completedText;

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _focusNode.requestFocus(),
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
                Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    height: _inputAreaHeight,
                    child: AnimatedBuilder(
                      animation: _shakeController,
                      builder: (context, child) {
                        final t = _shakeController.value;
                        final dx = t == 0 ? 0.0 : sin(t * pi * 6) * 10 * (1 - t);
                        return Transform.translate(offset: Offset(dx, 0), child: child);
                      },
                      child: completedText != null
                          ? CompletedCommand(
                              text: completedText,
                              animation: _strikeController,
                              style: inputStyle,
                            )
                          : TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              autofocus: true,
                              maxLines: null,
                              minLines: 1,
                              keyboardType: TextInputType.text,
                              textInputAction: TextInputAction.done,
                              textAlignVertical: TextAlignVertical.top,
                              onSubmitted: _confirm,
                              style: inputStyle,
                              cursorColor: colors.accent,
                              decoration: InputDecoration(
                                hintText: '...',
                                hintStyle: inputStyle.copyWith(color: colors.secondaryText),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                    ),
                  ),
                ),
                const Spacer(),
                FadeTransition(
                  opacity: _messageOpacity,
                  child: _lastResult != null
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ConfirmationPill(result: _lastResult!),
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
