import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/profile_exception.dart';

/// Reads the one thing the settings screen's membership card needs from
/// `profiles` beyond what [SessionService] already exposes: when the
/// account behind this shelf was first created — the card's own
/// "member since" line. Stateless, like `PurchasesService` — safe to
/// construct wherever it's needed rather than threading a single
/// instance through the tree.
class ProfileRepository {
  const ProfileRepository({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  static const _timeout = Duration(seconds: 10);

  /// When this account was created, or null if the row couldn't be
  /// read.
  Future<DateTime?> fetchJoinedAt(String userId) {
    return _run(() async {
      final row = await _client
          .from('profiles')
          .select('created_at')
          .eq('id', userId)
          .maybeSingle();
      final createdAt = row?['created_at'];
      return createdAt is String ? DateTime.tryParse(createdAt) : null;
    }, friendlyMessage: "We couldn't load your profile.");
  }

  /// Stamps which device last opened this account and when — what the
  /// library choice shows when an email is linked on a second device.
  Future<void> recordDevice(String userId, {String? deviceName}) {
    return _run<void>(() async {
      await _client
          .from('profiles')
          .update({
            'device_name': ?deviceName,
            'last_seen_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', userId);
    }, friendlyMessage: "We couldn't update your profile.");
  }

  Future<T> _run<T>(
    Future<T> Function() action, {
    required String friendlyMessage,
  }) async {
    try {
      return await action().timeout(_timeout);
    } on TimeoutException catch (error) {
      throw ProfileException(
        'That took too long. Check your connection and try again.',
        cause: error,
      );
    } on SocketException catch (error) {
      throw ProfileException(
        "You're offline — connect to the internet and try again.",
        cause: error,
      );
    } on http.ClientException catch (error) {
      throw ProfileException(
        "We couldn't reach the server. Try again in a moment.",
        cause: error,
      );
    } on Object catch (error) {
      // Covers PostgrestException and an uninitialized
      // `Supabase.instance` (an AssertionError, not an Exception) alike
      // — both need to degrade to a quiet failure rather than a crash.
      throw ProfileException(friendlyMessage, cause: error);
    }
  }
}
