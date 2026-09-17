import 'package:supabase_flutter/supabase_flutter.dart';

/// Whether a [PostgrestException] means the server couldn't serve the
/// request right now — worth retrying later — rather than a refusal of the
/// request itself.
///
/// `PostgrestException.code` is **not** an HTTP status in supabase_flutter
/// v2. It carries the Postgres SQLSTATE (`23505` unique violation, `23503`
/// foreign-key violation) or a PostgREST code (`PGRST116`), and only falls
/// back to the HTTP status when the response had no error body (a gateway
/// page). Reading it as a number and comparing with 500 used to classify
/// every constraint violation — `23505` and friends — as "unreachable":
/// the offline queue stalled behind that write forever and the app declared
/// itself offline while the backend was answering.
///
/// Transient means one of:
/// * a bare HTTP status of 500 or above (no error body);
/// * a SQLSTATE in a connection-level class — `08` connection exception,
///   `53` insufficient resources, `57` operator intervention, `58` system
///   error;
/// * a SQLSTATE that means "try again" — `40001` serialization failure,
///   `40P01` deadlock, `55P03` lock not available;
/// * PostgREST's own `PGRST000`–`PGRST003` (database unreachable, internal
///   connection error, schema cache not ready, pool timeout).
///
/// Anything else the server answered is a refusal; repeating the identical
/// request cannot help.
bool isTransientPostgrestError(PostgrestException error) {
  final code = (error.code ?? '').trim().toUpperCase();
  if (RegExp(r'^\d{3}$').hasMatch(code)) return int.parse(code) >= 500;
  if (RegExp(r'^PGRST00[0-3]$').hasMatch(code)) return true;
  if (const {'40001', '40P01', '55P03'}.contains(code)) return true;
  if (code.length == 5) {
    return const {'08', '53', '57', '58'}.contains(code.substring(0, 2));
  }
  return false;
}
