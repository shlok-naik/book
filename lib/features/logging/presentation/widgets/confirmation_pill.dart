import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';

/// How a command turned out, as far as the note under it says.
enum ConfirmationTone {
  /// It worked — an accent check.
  success,

  /// It was refused or failed — an ink cross.
  failure,

  /// Neither: the reader backed out, or it's plain information — a quiet
  /// dash, like a note in the margin.
  neutral,
}

/// The one-line note a command leaves behind — "Started "Dune"",
/// "Ratings are between 0.5 and 5 stars." — shown on the add tab, the
/// library, the book page and the editions page.
///
/// Written in the page's own voice rather than dropped on top of it: no
/// grey box, just a small mark saying how it went and the words beside it,
/// with any quoted book title set in the book-title face so it reads like
/// the title it is. The mark differs in *shape* as well as colour (a check,
/// a cross, a dash), so the outcome doesn't rest on colour alone.
///
/// [floating] is for where the note sits over other content (the library
/// grid): there it becomes a slip of the page's own paper with a hairline
/// edge, so it stays legible over covers without turning back into a grey
/// chip.
class ConfirmationPill extends StatelessWidget {
  const ConfirmationPill({
    super.key,
    required this.message,
    this.tone = ConfirmationTone.neutral,
    this.floating = false,
  });

  final String message;
  final ConfirmationTone tone;
  final bool floating;

  /// A quoted title inside a message — straight or curly quotes.
  static final _quoted = RegExp(r'"[^"]+"|“[^”]+”');

  @override
  Widget build(BuildContext context) {
    if (message.trim().isEmpty) return const SizedBox.shrink();
    final colors = context.colors;
    final fonts = context.fonts;

    final textStyle = fonts.interface(
      fontSize: 14,
      height: 1.4,
      color: colors.primaryText,
    );
    final titleStyle = fonts.bookTitle(
      fontSize: 15,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: colors.primaryText,
    );

    final note = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          // Centres the mark on the first line of text.
          padding: const EdgeInsets.only(top: 3),
          child: _Mark(tone: tone, colors: colors),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text.rich(
            TextSpan(style: textStyle, children: _spans(message, titleStyle)),
          ),
        ),
      ],
    );

    return Align(
      alignment: Alignment.centerLeft,
      child: floating
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: colors.divider),
                boxShadow: [
                  BoxShadow(
                    color: colors.primaryText.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm + 2,
                ),
                child: note,
              ),
            )
          : note,
    );
  }

  /// [message] split so each quoted title takes [titleStyle] — quotes kept,
  /// so the words are exactly what the command reported.
  static List<InlineSpan> _spans(String message, TextStyle titleStyle) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final match in _quoted.allMatches(message)) {
      if (match.start > last) {
        spans.add(TextSpan(text: message.substring(last, match.start)));
      }
      spans.add(TextSpan(text: match.group(0), style: titleStyle));
      last = match.end;
    }
    if (last < message.length) {
      spans.add(TextSpan(text: message.substring(last)));
    }
    return spans;
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.tone, required this.colors});

  final ConfirmationTone tone;
  final AppColors colors;

  static const _size = 16.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: switch (tone) {
        ConfirmationTone.success => Icon(
          Icons.check,
          size: _size,
          color: colors.accent,
        ),
        ConfirmationTone.failure => Icon(
          Icons.close,
          size: _size - 2,
          color: colors.primaryText,
        ),
        ConfirmationTone.neutral => Center(
          child: Container(
            width: 10,
            height: 1.5,
            decoration: BoxDecoration(
              color: colors.secondaryText,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
        ),
      },
    );
  }
}
