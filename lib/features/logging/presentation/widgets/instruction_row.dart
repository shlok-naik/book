import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// Where one AI-extracted instruction sits in its own execution — drives
/// [InstructionRow]'s visuals. Never optimistic: a row only reaches
/// [done] once its action has actually completed.
enum InstructionState { pending, done, error }

/// One line of an AI-extracted command list — a static analogue of
/// [CommandInput]'s own accept/reject sequence (same durations, same
/// curves), since an outcome here is meant to read as the same gesture
/// as one landing on the input field itself: [InstructionState.done]
/// strikes through and pops a checkmark exactly like an accepted
/// command, and [InstructionState.error] shakes exactly like a
/// rejected one — plain text throughout, no red or inline error label,
/// since [CommandInput] itself doesn't recolor a rejected line either;
/// the message goes in the shared pill instead. [CommandInput] drives
/// its own version of these from a live-typed, still-editable field;
/// this drives them from an externally-owned [state] instead, because
/// these lines are read-only history the moment they appear.
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
  // Matches CommandInput._acceptDuration/_strikeInterval/_checkInterval
  // exactly — the whole point is that this reads as the same gesture.
  static const _acceptDuration = Duration(milliseconds: 700);
  static const _strikeInterval = Interval(0, 0.55, curve: Curves.easeOut);
  static const _checkInterval = Interval(0.45, 1, curve: Curves.elasticOut);
  static const _iconSize = 16.0;

  // Matches CommandInput._shakeDuration and its translate formula too.
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: AnimatedBuilder(
        animation: Listenable.merge([_accept, _shake]),
        builder: (context, _) {
          final struck = (widget.text.length * _strike.value)
              .round()
              .clamp(0, widget.text.length);
          final shake = _shake.value;
          final dx = shake == 0 ? 0.0 : sin(shake * pi * 6) * 8 * (1 - shake);

          return Transform.translate(
            offset: Offset(dx, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: widget.style,
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
                ),
                const SizedBox(width: AppSpacing.xs),
                Transform.scale(
                  scale: _check.value,
                  child: Icon(
                    Icons.check_circle,
                    size: _iconSize,
                    color: colors.accent,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
