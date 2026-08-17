import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// A [TextEditingController] that can strike a line through a leading
/// run of its own text.
///
/// The strikethrough is a [TextDecoration] applied to the text the field
/// is *already* rendering, rather than something drawn by a second
/// widget standing in for the field. That distinction is the whole point:
/// decorations are painted, never measured, so the glyphs keep their
/// exact size, position, and line breaks while the line crosses them.
/// Any stand-in widget re-lays-out the text under its own constraints
/// and shifts it, however carefully its padding is matched.
class StrikethroughTextEditingController extends TextEditingController {
  /// Line weight, as a multiplier of the thickness the font defines for
  /// its own strikethrough — not a pixel value.
  static const _thickness = 2.0;

  double _strikeProgress = 0;

  /// How much of the text is struck through, from 0 (none) to 1 (all).
  ///
  /// Setting this re-renders the field without touching its value or
  /// selection, so driving it from an animation never disturbs what the
  /// reader typed or where the cursor is.
  double get strikeProgress => _strikeProgress;

  set strikeProgress(double value) {
    final clamped = value.clamp(0.0, 1.0);
    if (_strikeProgress == clamped) return;
    _strikeProgress = clamped;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // Stepped per character rather than per pixel: the field's font is
    // monospaced, so every glyph advances by the same width and the line
    // still grows at a visually constant rate — while always ending on a
    // glyph boundary instead of halfway through one.
    final struck = (text.length * _strikeProgress).round().clamp(
      0,
      text.length,
    );

    // Nothing struck yet — defer to the default, which also handles the
    // IME composing underline that the split span below would drop.
    if (struck == 0) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    return TextSpan(
      style: style,
      children: [
        TextSpan(
          text: text.substring(0, struck),
          style: TextStyle(
            decoration: TextDecoration.lineThrough,
            // Read off the live theme rather than captured at
            // construction, so a light/dark switch mid-strike is
            // picked up. The glyphs keep the field's own color —
            // dimming them reads as a size change even at an
            // identical font size (a contrast illusion).
            decorationColor: context.colors.accent,
            decorationThickness: _thickness,
          ),
        ),
        if (struck < text.length) TextSpan(text: text.substring(struck)),
      ],
    );
  }
}
