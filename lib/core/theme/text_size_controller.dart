import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics/app_logger.dart';

/// How big the app's text is, on top of the phone's own text size — settings'
/// **text size** rows. Many readers never find the system setting; this is
/// one tap away in the app itself.
enum TextSize {
  standard('standard', 1),
  large('large', 1.15),
  largest('largest', 1.3);

  const TextSize(this.label, this.factor);

  final String label;
  final double factor;
}

/// The reader's [TextSize], on the device like `StartPageController`.
class TextSizeController {
  TextSizeController._();

  static const _key = 'appearance.text_size';

  static final ValueNotifier<TextSize> size = ValueNotifier(TextSize.standard);

  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      size.value = TextSize.values.firstWhere(
        (s) => s.name == saved,
        orElse: () => TextSize.standard,
      );
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'TextSizeController',
        'Could not read the saved text size.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static Future<void> select(TextSize next) async {
    size.value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, next.name);
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'TextSizeController',
        'Could not save the text size.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @visibleForTesting
  static void reset() => size.value = TextSize.standard;
}

/// Scales [child]'s text by the reader's [TextSize] on top of the system
/// scaler already in the [MediaQuery] — never below it, and capped so the
/// two together can't make a screen unusable.
class ReaderTextScale extends StatelessWidget {
  const ReaderTextScale({super.key, required this.child});

  final Widget child;

  /// The most the system and in-app sizes may add up to.
  static const maxScale = 2.4;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextSize>(
      valueListenable: TextSizeController.size,
      child: child,
      builder: (context, size, child) {
        if (size == TextSize.standard) return child!;
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: _MultipliedTextScaler(media.textScaler, size.factor),
          ),
          child: child!,
        );
      },
    );
  }
}

class _MultipliedTextScaler extends TextScaler {
  const _MultipliedTextScaler(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) {
    final system = base.scale(fontSize);
    final capped = math.min(
      system * factor,
      fontSize * ReaderTextScale.maxScale,
    );
    // Never smaller than the system size alone.
    return math.max(capped, system);
  }

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * factor;

  @override
  bool operator ==(Object other) =>
      other is _MultipliedTextScaler &&
      other.base == base &&
      other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}
