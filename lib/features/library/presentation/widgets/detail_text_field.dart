import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';

/// The text field the book detail page uses for page/percent, tags and
/// comments — the same outlined, background-filled look as the email
/// sheet's field in settings, so the app has one text-field style rather
/// than a new one per screen.
class DetailTextField extends StatelessWidget {
  const DetailTextField({
    super.key,
    required this.controller,
    required this.hintText,
    this.onSubmitted,
    this.onChanged,
    this.keyboardType,
    this.inputFormatters,
    this.maxLength,
    this.maxLines = 1,
    this.enabled = true,
    this.suffixText,
    this.textInputAction,
    this.semanticsLabel,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  /// Enforced while typing, without the default visible counter — the
  /// repository's own validation carries the message for anything longer.
  final int? maxLength;
  final int maxLines;
  final bool enabled;
  final String? suffixText;
  final TextInputAction? textInputAction;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = context.fonts.body(fontSize: 15, color: colors.primaryText);
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: color),
    );

    return Semantics(
      label: semanticsLabel,
      textField: true,
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        inputFormatters: [
          ...?inputFormatters,
          if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
        ],
        maxLines: maxLines,
        minLines: 1,
        textInputAction:
            textInputAction ??
            (maxLines == 1 ? TextInputAction.done : TextInputAction.newline),
        onSubmitted: onSubmitted,
        // Enter submits without closing the keyboard (a TextField's default
        // is to unfocus on the action button).
        onEditingComplete: () {},
        onChanged: onChanged,
        style: style,
        cursorColor: colors.accent,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: style.copyWith(color: colors.secondaryText),
          suffixText: suffixText,
          suffixStyle: context.fonts.interface(
            fontSize: 13,
            color: colors.secondaryText,
          ),
          isDense: true,
          filled: true,
          fillColor: colors.background,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 4,
          ),
          border: border(colors.divider),
          enabledBorder: border(colors.divider),
          disabledBorder: border(colors.divider.withValues(alpha: 0.5)),
          focusedBorder: border(colors.accent),
        ),
      ),
    );
  }
}
