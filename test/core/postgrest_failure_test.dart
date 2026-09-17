import 'package:book/core/supabase/postgrest_failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

PostgrestException _error(String? code) =>
    PostgrestException(message: 'x', code: code);

void main() {
  // Regression: `23505` parsed as a number is >= 500, so a unique violation
  // used to read as "unreachable" — stalling the offline queue forever and
  // marking the app offline while the backend was answering.
  test('constraint and permission errors are refusals, not outages', () {
    for (final code in [
      '23505',
      '23503',
      '23514',
      '42501',
      'PGRST116',
      '22P02',
    ]) {
      expect(isTransientPostgrestError(_error(code)), isFalse, reason: code);
    }
  });

  test('connection-level SQLSTATE classes are transient', () {
    for (final code in ['08006', '53300', '57P01', '58030']) {
      expect(isTransientPostgrestError(_error(code)), isTrue, reason: code);
    }
  });

  test("PostgREST's own connection failures are transient", () {
    for (final code in ['PGRST000', 'PGRST001', 'PGRST002', 'PGRST003']) {
      expect(isTransientPostgrestError(_error(code)), isTrue, reason: code);
    }
  });

  test('a bare HTTP status counts only when it is a server error', () {
    expect(isTransientPostgrestError(_error('503')), isTrue);
    expect(isTransientPostgrestError(_error('500')), isTrue);
    expect(isTransientPostgrestError(_error('404')), isFalse);
    expect(isTransientPostgrestError(_error(null)), isFalse);
  });

  test('retryable SQLSTATEs are transient', () {
    for (final code in ['40001', '40P01', '55P03']) {
      expect(isTransientPostgrestError(_error(code)), isTrue, reason: code);
    }
  });
}
