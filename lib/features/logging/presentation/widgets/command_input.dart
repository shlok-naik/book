import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'strikethrough_text_editing_controller.dart';

/// Runs a submitted command.
///
/// Returning true accepts it — the line is struck through, a checkmark
/// pops in, and the field clears. Returning false rejects it — the field
/// shakes and keeps the text, ready to be corrected.
typedef CommandSubmitHandler = Future<bool> Function(String command);

/// The log page's command line.
///
/// One [TextField] stays mounted for a command's whole lifecycle —
/// typing, submitting, accepting, rejecting. Every state is expressed
/// either by painting over that field (a strikethrough decoration on its
/// own text, a checkmark overlaid in a [Stack]) or by translating it as
/// a whole (the reject shake). The field is never swapped for a
/// look-alike, which is what keeps the typed text at exactly the same
/// size and position from the keystroke that entered it to the frame
/// that clears it.
class CommandInput extends StatefulWidget {
  const CommandInput({
    super.key,
    required this.focusNode,
    required this.style,
    required this.onSubmit,
    this.hintText = '...',
  });

  /// Owned by the caller, so the page can hand focus back to the field
  /// when the reader taps anywhere on it.
  final FocusNode focusNode;

  /// Type style for the field. Its `fontSize` and `height` also set the
  /// line box the checkmark centers itself against.
  final TextStyle style;

  final CommandSubmitHandler onSubmit;

  final String hintText;

  @override
  State<CommandInput> createState() => _CommandInputState();
}

class _CommandInputState extends State<CommandInput>
    with TickerProviderStateMixin {
  /// Fixed height for the whole control, so neither the shake nor the
  /// checkmark nor a long command can nudge the page's layout.
  static const _height = 48.0;

  /// One controller drives the accept sequence; the two phases are cut
  /// out of it with intervals, so the checkmark can start before the
  /// line has finished crossing and the two read as a single gesture.
  static const _acceptDuration = Duration(milliseconds: 700);
  static const _strikeInterval = Interval(0, 0.55, curve: Curves.easeOut);
  static const _checkInterval = Interval(0.45, 1, curve: Curves.elasticOut);

  /// How long the struck-through command stays up, after the animation,
  /// before the field clears — long enough to read what was logged.
  static const _holdAfterAccept = Duration(milliseconds: 520);

  static const _shakeDuration = Duration(milliseconds: 400);

  static const _checkSize = 22.0;
  static const _checkGap = 10.0;

  final _text = StrikethroughTextEditingController();

  late final AnimationController _accept = AnimationController(
    vsync: this,
    duration: _acceptDuration,
  );
  late final Animation<double> _strike = CurvedAnimation(
    parent: _accept,
    curve: _strikeInterval,
  );
  late final Animation<double> _check = CurvedAnimation(
    parent: _accept,
    curve: _checkInterval,
  );

  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: _shakeDuration,
  );

  /// True from submit until the command has fully resolved. Blocks edits
  /// and a second submit while the library call is in flight, so a
  /// double-tap of the return key can't fire the same command twice.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _strike.addListener(_syncStrike);
  }

  /// Hands the strike animation's value to the controller, which is what
  /// actually renders the line — the animation never touches the text.
  void _syncStrike() => _text.strikeProgress = _strike.value;

  @override
  void dispose() {
    _strike.removeListener(_syncStrike);
    (_strike as CurvedAnimation).dispose();
    (_check as CurvedAnimation).dispose();
    _accept.dispose();
    _shake.dispose();
    _text.dispose();
    super.dispose();
  }

  /// Submits the current line and plays whichever outcome comes back.
  ///
  /// The accept animation deliberately waits on [CommandInput.onSubmit]
  /// rather than running optimistically: a command can parse cleanly and
  /// still fail to apply (offline, a book already on the shelf, a page
  /// past the end), and a strike-through that plays before the outcome
  /// is known would report those failures as successes.
  Future<void> _submit(String raw) async {
    final command = raw.trim();
    if (command.isEmpty || _busy) return;

    setState(() => _busy = true);
    final accepted = await widget.onSubmit(command);
    if (!mounted) return;

    if (!accepted) {
      setState(() => _busy = false);
      _shake.forward(from: 0);
      widget.focusNode.requestFocus();
      return;
    }

    await _accept.forward(from: 0);
    if (!mounted) return;
    await Future<void>.delayed(_holdAfterAccept);
    if (!mounted) return;

    _text.clear();
    _text.strikeProgress = 0;
    _accept.value = 0;
    setState(() => _busy = false);
    widget.focusNode.requestFocus();
  }

  /// Where the checkmark sits: just past the end of the typed text,
  /// clamped so a command wider than the field parks it at the right
  /// edge instead of pushing it out of view.
  ///
  /// Measured with a [TextPainter] rather than laid out in a [Row]. A row
  /// would have to take width away from the field to make room, moving
  /// the text — the exact thing this control exists to avoid — whereas a
  /// measurement that turns out a pixel off only misplaces the checkmark.
  double _checkmarkLeft(double maxWidth) {
    final painter = TextPainter(
      text: TextSpan(text: _text.text, style: widget.style),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final textWidth = painter.width;
    painter.dispose();

    return min(textWidth + _checkGap, maxWidth - _checkSize);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = widget.style;
    // The text's own line box, so the checkmark centers against the text
    // rather than against the taller control.
    final lineHeight = (style.fontSize ?? 24) * (style.height ?? 1);

    return SizedBox(
      width: double.infinity,
      height: _height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return AnimatedBuilder(
            animation: Listenable.merge([_accept, _shake, _text]),
            builder: (context, _) {
              final shake = _shake.value;
              final dx = shake == 0
                  ? 0.0
                  : sin(shake * pi * 6) * 10 * (1 - shake);

              return Transform.translate(
                offset: Offset(dx, 0),
                child: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: [
                    TextField(
                      controller: _text,
                      focusNode: widget.focusNode,
                      autofocus: true,
                      // Single line on purpose: the control's height is
                      // fixed, so a wrapping field would overflow it, and
                      // re-wrapping mid-command would move the text.
                      maxLines: 1,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.done,
                      textAlignVertical: TextAlignVertical.top,
                      readOnly: _busy,
                      showCursor: !_busy,
                      onSubmitted: _submit,
                      style: style,
                      cursorColor: colors.accent,
                      decoration: InputDecoration(
                        hintText: widget.hintText,
                        hintStyle: style.copyWith(
                          color: colors.secondaryText,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    // Overlaid, never laid out beside the field, so it
                    // cannot take width from the text.
                    Positioned(
                      left: _checkmarkLeft(constraints.maxWidth),
                      top: 0,
                      height: lineHeight,
                      child: Center(
                        child: Transform.scale(
                          // elasticOut overshoots past 1 on the way in,
                          // which is what gives the checkmark its pop.
                          scale: _check.value,
                          child: Icon(
                            Icons.check_circle,
                            size: _checkSize,
                            color: colors.accent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
