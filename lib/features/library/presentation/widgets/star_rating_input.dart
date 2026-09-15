import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/formatting/numbers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_spacing.dart';

/// Five tappable stars with half-star precision: tapping the left half of
/// a star gives it a half, the right half a whole. The book tile's own
/// read-only row uses the same full/half/outline icons, so what a reader
/// picks here is exactly what the shelf then shows.
///
/// Usable without a pointer, too: the row is one focusable control that
/// arrow keys move by half a star (Home/End for 0.5 and 5), and to a
/// screen reader it is a single adjustable control ("4.5 of 5 stars",
/// swipe up/down to change) rather than five separate buttons.
///
/// [onChanged] null renders the row disabled (faded, inert, not focusable)
/// — used for a book that isn't finished yet, which
/// `LibraryController.rateBook` would refuse anyway.
class StarRatingInput extends StatefulWidget {
  const StarRatingInput({super.key, required this.rating, this.onChanged});

  final double? rating;
  final ValueChanged<double>? onChanged;

  @override
  State<StarRatingInput> createState() => _StarRatingInputState();
}

class _StarRatingInputState extends State<StarRatingInput> {
  static const _starSize = 32.0;
  static const _step = 0.5;

  bool _focused = false;

  bool get _enabled => widget.onChanged != null;

  void _set(double value) {
    final clamped = value.clamp(_step, 5.0);
    if (clamped == widget.rating) return;
    widget.onChanged?.call(clamped);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_enabled || event is KeyUpEvent) return KeyEventResult.ignored;
    final current = widget.rating ?? 0;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp) {
      _set(current + _step);
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowDown) {
      _set(current - _step);
    } else if (key == LogicalKeyboardKey.home) {
      _set(_step);
    } else if (key == LogicalKeyboardKey.end) {
      _set(5);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  static String _format(double rating) => formatCompactNumber(rating);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final value = widget.rating ?? 0;
    final rating = widget.rating;

    final stars = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _enabled
                ? (details) {
                    final half = details.localPosition.dx < _starSize / 2;
                    _set(i + (half ? 0.5 : 1.0));
                  }
                : null,
            child: SizedBox(
              width: _starSize,
              height: _starSize + AppSpacing.xs,
              child: Icon(
                value >= i + 1
                    ? Icons.star
                    : value >= i + 0.5
                    ? Icons.star_half
                    : Icons.star_border,
                size: _starSize - 4,
                color: colors.accent,
              ),
            ),
          ),
        if (rating != null) ...[
          const SizedBox(width: AppSpacing.sm),
          Text(
            _format(rating),
            style: context.fonts.interface(fontSize: 14, color: colors.accent),
          ),
        ],
      ],
    );

    return Semantics(
      slider: _enabled,
      label: 'Your rating',
      value: rating == null ? 'Not rated' : '${_format(rating)} of 5 stars',
      increasedValue: _enabled
          ? '${_format((value + _step).clamp(_step, 5.0))} of 5 stars'
          : null,
      decreasedValue: _enabled
          ? '${_format((value - _step).clamp(_step, 5.0))} of 5 stars'
          : null,
      onIncrease: _enabled ? () => _set(value + _step) : null,
      onDecrease: _enabled ? () => _set(value - _step) : null,
      excludeSemantics: true,
      child: Focus(
        canRequestFocus: _enabled,
        skipTraversal: !_enabled,
        onKeyEvent: _onKey,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: Opacity(
          opacity: _enabled ? 1 : 0.4,
          child: MouseRegion(
            cursor: _enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _focused ? colors.accent : Colors.transparent,
                  width: 2,
                ),
              ),
              child: stars,
            ),
          ),
        ),
      ),
    );
  }
}
