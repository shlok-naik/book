import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/diagnostics/app_logger.dart';
import '../domain/profile_identity.dart';

/// The reader's [ProfileIdentity]. On the device for now, like
/// `StartPageController`: the hosted `profiles` table has no column for it,
/// so the name doesn't follow the reader to another device.
class ProfileIdentityController {
  ProfileIdentityController._();

  static const _displayNameKey = 'profile.display_name';

  /// The `@username` an earlier build stored; removed on load.
  static const _legacyUsernameKey = 'profile.username';

  static final ValueNotifier<ProfileIdentity> identity = ValueNotifier(
    ProfileIdentity.empty,
  );

  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      identity.value = ProfileIdentity(
        displayName: _nonEmpty(prefs.getString(_displayNameKey)),
      );
      await prefs.remove(_legacyUsernameKey);
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'ProfileIdentityController',
        'Could not read the saved profile.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Saves the name, trimmed. Returns a message instead of saving when it is
  /// empty or too long — a name is required.
  static Future<String?> save({required String displayName}) async {
    final error = ProfileNames.displayNameError(displayName);
    if (error != null) return error;
    final next = ProfileIdentity(displayName: displayName.trim());
    identity.value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_displayNameKey, next.displayName!);
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'ProfileIdentityController',
        'Could not save the profile.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return null;
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  @visibleForTesting
  static void reset([ProfileIdentity value = ProfileIdentity.empty]) =>
      identity.value = value;
}
