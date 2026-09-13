import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/reading_goal.dart';

/// Reads and writes `profiles.reading_goal` — the reader's yearly target.
/// The row itself always exists (the `handle_new_user` trigger creates it),
/// so this only ever selects and updates it.
class GoalRepository {
  GoalRepository({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  static const _timeout = Duration(seconds: 10);

  /// The saved goal, or null when the reader hasn't set one.
  Future<int?> fetchGoal() {
    return _run(() async {
      final row = await _client
          .from('profiles')
          .select('reading_goal')
          .eq('id', _userId)
          .maybeSingle();
      final goal = row?['reading_goal'];
      return goal is num ? goal.toInt() : null;
    }, friendlyMessage: "We couldn't load your reading goal.");
  }

  /// Saves [goal], or clears it with null.
  Future<void> saveGoal(int? goal) {
    if (goal != null && !ReadingGoal.isValid(goal)) {
      throw GoalException(
        'A goal has to be between ${ReadingGoal.min} and ${ReadingGoal.max} '
        'books.',
      );
    }
    return _run<void>(() async {
      await _client
          .from('profiles')
          .update({'reading_goal': goal})
          .eq('id', _userId);
    }, friendlyMessage: "We couldn't save your reading goal.");
  }

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const GoalException("You're not signed in yet.");
    return id;
  }

  Future<T> _run<T>(
    Future<T> Function() action, {
    required String friendlyMessage,
  }) async {
    try {
      return await action().timeout(_timeout);
    } on GoalException {
      rethrow;
    } on TimeoutException catch (error) {
      throw GoalException(
        'That took too long. Check your connection and try again.',
        cause: error,
      );
    } on SocketException catch (error) {
      throw GoalException(
        "You're offline — connect to the internet and try again.",
        cause: error,
      );
    } on http.ClientException catch (error) {
      throw GoalException(
        "We couldn't reach the server. Try again in a moment.",
        cause: error,
      );
    } on Object catch (error) {
      throw GoalException(friendlyMessage, cause: error);
    }
  }
}
