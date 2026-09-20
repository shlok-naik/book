import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/diagnostics/app_logger.dart';
import '../../settings/data/profile_repository.dart';
import '../domain/profile_identity.dart';

/// The reader's [ProfileIdentity]. Kept on the device so it is there before
/// the network is, and mirrored to `profiles.display_name` once [attach]ed,
/// so it follows the reader to another device or through an email link.
class ProfileIdentityController {
  ProfileIdentityController._();

  static const _displayNameKey = 'profile.display_name';

  /// The `@username` an earlier build stored; removed on load.
  static const _legacyUsernameKey = 'profile.username';

  static final ValueNotifier<ProfileIdentity> identity = ValueNotifier(
    ProfileIdentity.empty,
  );

  static ProfileRepository? _remote;
  static String? Function()? _userId;

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

  /// Connects the account: from now on a saved name is also written to the
  /// profile row. Never called in tests, where there is no server.
  static void attach({
    required ProfileRepository repository,
    required String? Function() userId,
  }) {
    _remote = repository;
    _userId = userId;
  }

  /// Reconciles the device with the account. An account that has a name
  /// wins (a new phone, or an email link that swapped libraries); one that
  /// has none takes this device's. Never throws.
  static Future<void> syncWithAccount() async {
    final remote = _remote;
    final userId = _userId?.call();
    if (remote == null || userId == null) return;
    try {
      final saved = await remote.fetchDisplayName(userId);
      if (saved != null) {
        if (saved != identity.value.displayName) {
          identity.value = ProfileIdentity(displayName: saved);
          await _writeLocal(saved);
        }
      } else if (identity.value.displayName case final local?) {
        await remote.saveDisplayName(userId, local);
      }
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'ProfileIdentityController',
        'Could not sync the name with the account.',
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
    final name = displayName.trim();
    identity.value = ProfileIdentity(displayName: name);
    await _writeLocal(name);
    final remote = _remote;
    final userId = _userId?.call();
    if (remote != null && userId != null) {
      try {
        await remote.saveDisplayName(userId, name);
      } on Object catch (error, stackTrace) {
        // The device has it; the next launch's sync pushes it up.
        AppLogger.warning(
          'ProfileIdentityController',
          'Could not save the name to the account.',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return null;
  }

  static Future<void> _writeLocal(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_displayNameKey, name);
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'ProfileIdentityController',
        'Could not save the profile.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  @visibleForTesting
  static void reset([ProfileIdentity value = ProfileIdentity.empty]) {
    identity.value = value;
    _remote = null;
    _userId = null;
  }
}
