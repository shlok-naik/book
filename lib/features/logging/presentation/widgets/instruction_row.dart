import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Where one AI-extracted instruction sits in its own execution — drives
/// [InstructionRow]'s visuals. Never optimistic: a row only reaches
/// [done] once its action has actually completed.
enum InstructionState { pending, done, error }

/// Marks text as AI-produced — shared by [InstructionRow] (every line
/// Groq generated) and `HomePage`'s "still thinking" shimmer, so the
/// gradient always means the same thing wherever it shows up.
const aiGradient = LinearGradient(
  colors: [Color(0xFF2DD4BF), Color(0xFF8B5CF6), Color(0xFFEC4899)],
);

/// One line of an AI-extracted command list — a static analogue of
/// [CommandInput]'s own accept/reject sequence (same durations, same
/// curves, same checkmark-placement math), since an outcome here is
/// meant to read as the exact same gesture as one landing on the input
/// field itself: [InstructionState.done] strikes through and pops a
/// checkmark exactly like an accepted command, and [InstructionState.
/// error] shakes exactly like a rejected one. [CommandInput] drives
/// its own version of these from a live-typed, still-editable field;
/// this drives them from an externally-owned [state] instead, because
/// these lines are read-only history the moment they appear.
///
/// Only the glyphs themselves carry [aiGradient] — via a [Paint]
/// shader on the text's `foreground`, not a [ShaderMask] wrapping the
/// whole row, since that would just as easily repaint the strike-
/// through line and the checkmark, and those two are meant to read as
/// the exact same accept/reject system every other command in the app
/// uses, in the app's own plain accent color, not the AI's.
class InstructionRow extends StatefulWidget {
  const InstructionRow({
    super.key,
    required this.text,
    required this.state,
    required this.style,
  });

  final String text;
  final InstructionState state;
  final TextStyle style;

  @override
  State<InstructionRow> createState() => _InstructionRowState();
}

class _InstructionRowState extends State<InstructionRow>
    with TickerProviderStateMixin {
  // Matches CommandInput's own accept/shake constants and checkmark
  // placement exactly — the whole point is that this reads as the
  // same gesture, in the same spot relative to the text, not just the
  // same colors and timings.
  static const _acceptDuration = Duration(milliseconds: 700);
  static const _strikeInterval = Interval(0, 0.55, curve: Curves.easeOut);
  static const _checkInterval = Interval(0.45, 1, curve: Curves.elasticOut);
  static const _checkSize = 22.0;
  static const _checkGap = 10.0;

  static const _shakeDuration = Duration(milliseconds: 400);

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

  @override
  void didUpdateWidget(covariant InstructionRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state == widget.state) return;
    switch (widget.state) {
      case InstructionState.done:
        _accept.forward(from: 0);
      case InstructionState.error:
        _shake.forward(from: 0);
      case InstructionState.pending:
        break;
    }
  }

  @override
  void dispose() {
    (_strike as CurvedAnimation).dispose();
    (_check as CurvedAnimation).dispose();
    _accept.dispose();
    _shake.dispose();
    super.dispose();
  }

  /// Where the checkmark sits: just past the end of the line, wherever
  /// that lands once it wraps — the exact same measurement
  /// [CommandInput] does for its own checkmark, just against
  /// [widget.text] instead of a live controller's current value.
  Offset _checkmarkOffset(double maxWidth) {
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      textDirection: Directionality.of(context),
    )..layout(maxWidth: maxWidth);
    final caret = painter.getOffsetForCaret(
      TextPosition(offset: widget.text.length),
      Rect.zero,
    );
    painter.dispose();

    final left = min(caret.dx + _checkGap, maxWidth - _checkSize);
    return Offset(left < 0 ? 0 : left, caret.dy);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // The text's own line box, so the checkmark centers against the
    // line it trails — matches CommandInput's own.
    final lineHeight = (widget.style.fontSize ?? 24) * (widget.style.height ?? 1);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // One shader for the whole line, sized to it, so the gradient
          // reads the same regardless of how long the text is.
          final gradientFill = Paint()
            ..shader = aiGradient.createShader(
              Rect.fromLTWH(0, 0, constraints.maxWidth, lineHeight),
            );
          final checkmark = _checkmarkOffset(constraints.maxWidth);

          return AnimatedBuilder(
            animation: Listenable.merge([_accept, _shake]),
            builder: (context, _) {
              final struck = (widget.text.length * _strike.value)
                  .round()
                  .clamp(0, widget.text.length);
              final shake = _shake.value;
              final dx = shake == 0
                  ? 0.0
                  : sin(shake * pi * 6) * 8 * (1 - shake);

              return Transform.translate(
                offset: Offset(dx, 0),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: widget.style.copyWith(foreground: gradientFill),
                        children: [
                          TextSpan(
                            text: widget.text.substring(0, struck),
                            style: TextStyle(
                              decoration: TextDecoration.lineThrough,
                              decorationColor: colors.accent,
                              decorationThickness: 2,
                            ),
                          ),
                          if (struck < widget.text.length)
                            TextSpan(text: widget.text.substring(struck)),
                        ],
                      ),
                    ),
                    // Overlaid, never laid out beside the text, so it
                    // cannot take width from it — same reasoning as
                    // CommandInput's own checkmark.
                    Positioned(
                      left: checkmark.dx,
                      top: checkmark.dy,
                      height: lineHeight,
                      child: Center(
                        child: Transform.scale(
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
