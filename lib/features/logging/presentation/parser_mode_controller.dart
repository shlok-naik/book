import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/diagnostics/app_logger.dart';
import '../../../core/purchases/plan_controller.dart';

/// How the add tab reads what's typed.
enum ParserMode {
  /// `LogCommandParser` alone — the exact command grammar.
  classic('classic'),

  /// `SmartCommandParser` on the device: plain sentences, typos, several
  /// actions at once, and the book picker when a book is unclear.
  beta('beta parser'),

  /// The `parse-command` edge function — cactus pro's natural language.
  proAi('pro ai');

  const ParserMode(this.label);

  final String label;
}

/// Which parser the add tab uses. Chosen in settings' **debug** section
/// (debug builds only). Until something is chosen, and always in a release
/// build, it follows the plan: pro AI for cactus pro, the beta parser
/// otherwise ([effective]).
class ParserModeController {
  ParserModeController._();

  static const _key = 'debug.parser_mode';

  /// The debug choice; null follows the plan.
  static final ValueNotifier<ParserMode?> chosen = ValueNotifier(null);

  /// The plan's own parser: the AI for cactus pro, and the on-device beta
  /// parser — plain sentences — for everyone else.
  static ParserMode get planDefault =>
      PlanController.isPro.value ? ParserMode.proAi : ParserMode.beta;

  /// What actually runs. Offline, the AI can't, so a pro AI choice falls
  /// back to the beta parser, which runs on the device.
  static ParserMode effective({required bool offline}) {
    final mode = (kDebugMode ? chosen.value : null) ?? planDefault;
    return mode == ParserMode.proAi && offline ? ParserMode.beta : mode;
  }

  static Future<void> initialize() async {
    if (!kDebugMode) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      for (final mode in ParserMode.values) {
        if (mode.name == saved) chosen.value = mode;
      }
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'ParserModeController',
        'Could not read the saved parser mode; following the plan.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static Future<void> select(ParserMode mode) async {
    chosen.value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'ParserModeController',
        'Could not save the parser mode.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @visibleForTesting
  static void reset() => chosen.value = null;
}
