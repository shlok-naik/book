import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/diagnostics/app_logger.dart';
import '../domain/profile_identity.dart';

/// The reader's [ProfileIdentity]. On the device for now, like
/// `StartPageController`: the hosted database has no columns for it yet
/// (`supabase/migrations/20260924000000_profile_identity.sql` is written
/// but not applied), so a username doesn't follow the reader to another
/// device and isn't checked for uniqueness.
class ProfileIdentityController {
  ProfileIdentityController._();

  static const _usernameKey = 'profile.username';
  static const _displayNameKey = 'profile.display_name';

  static final ValueNotifier<ProfileIdentity> identity = ValueNotifier(
    ProfileIdentity.empty,
  );

  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      identity.value = ProfileIdentity(
        username: _nonEmpty(prefs.getString(_usernameKey)),
        displayName: _nonEmpty(prefs.getString(_displayNameKey)),
      );
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'ProfileIdentityController',
        'Could not read the saved profile.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Saves both names, normalized; an empty value clears that name. Returns
  /// a message instead of saving when either is invalid.
  static Future<String?> save({
    required String username,
    required String displayName,
  }) async {
    final error =
        ProfileNames.usernameError(username) ??
        ProfileNames.displayNameError(displayName);
    if (error != null) return error;
    final next = ProfileIdentity(
      username: _nonEmpty(ProfileNames.normalizeUsername(username)),
      displayName: _nonEmpty(displayName),
    );
    identity.value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await _write(prefs, _usernameKey, next.username);
      await _write(prefs, _displayNameKey, next.displayName);
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

  static Future<void> _write(
    SharedPreferences prefs,
    String key,
    String? value,
  ) async {
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  @visibleForTesting
  static void reset([ProfileIdentity value = ProfileIdentity.empty]) =>
      identity.value = value;
}
