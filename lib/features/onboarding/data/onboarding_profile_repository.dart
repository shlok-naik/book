import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/onboarding_averages.dart';
import '../domain/onboarding_profile_draft.dart';
import 'session_service.dart' show OnboardingException;

/// Reads and writes the Supabase `profiles` table (see
/// `supabase/schema.sql`) — the answers collected across onboarding,
/// and the aggregate averages Q1/Q2 show back.
class OnboardingProfileRepository {
  /// As in `SessionService`/`UserBookRepository`, the client is resolved
  /// lazily so this can exist before `Supabase.initialize` has run.
  OnboardingProfileRepository({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  static const _table = 'profiles';

  /// Updates whatever fields [draft] carries against the signed-in
  /// reader's row. Only called once an account exists (right after
  /// verifying the onboarding email code), so `auth.uid()` is always
  /// resolvable, and only ever an UPDATE — a blank row is created for
  /// every reader the moment their account is, by a database trigger,
  /// so there's never an insert-vs-update decision to make here.
  Future<void> saveProfile(OnboardingProfileDraft draft) {
    return _run(() async {
      final values = <String, Object?>{};
      if (draft.readingGoal != null) values['reading_goal'] = draft.readingGoal;
      if (draft.readingMinutesPerDay != null) {
        values['reading_minutes_per_day'] = draft.readingMinutesPerDay;
      }
      if (draft.name != null && draft.name!.isNotEmpty) values['name'] = draft.name;
      if (draft.description != null && draft.description!.isNotEmpty) {
        values['description'] = draft.description;
      }
      if (values.isEmpty) return;

      await _client.from(_table).update(values);
    });
  }

  /// The signed-in reader's stored name, or null if they never set one.
  /// Only meaningful for an account that already existed before this
  /// session — see `SessionService.isExistingAccount` — since a brand
  /// new row's `name` column is blank until onboarding saves it.
  Future<String?> fetchName() {
    return _run(() async {
      final row = await _client.from(_table).select('name').maybeSingle();
      final name = row?['name'] as String?;
      return (name == null || name.isEmpty) ? null : name;
    });
  }

  /// The average reading goal and reading time across every reader who
  /// has answered Q1/Q2 — via a `security definer` RPC so this works
  /// before the caller has an account of their own and without needing
  /// read access to any other reader's row.
  Future<OnboardingAverages> fetchAverages() {
    return _run(() async {
      final rows = await _client.rpc('onboarding_averages') as List;
      if (rows.isEmpty) return const OnboardingAverages();
      final row = rows.first as Map<String, dynamic>;
      return OnboardingAverages(
        readingGoal: (row['avg_reading_goal'] as num?)?.round(),
        readingMinutesPerDay: (row['avg_reading_minutes'] as num?)?.round(),
      );
    });
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (error) {
      throw OnboardingException("We couldn't save that.", cause: error);
    } on TimeoutException catch (error) {
      throw OnboardingException(
        'That took too long. Check your connection and try again.',
        cause: error,
      );
    } on SocketException catch (error) {
      throw OnboardingException(
        "You're offline — connect to the internet and try again.",
        cause: error,
      );
    } on http.ClientException catch (error) {
      throw OnboardingException(
        "We couldn't reach the server. Try again in a moment.",
        cause: error,
      );
    }
  }
}
