/// A failure from any [ProfileRepository] call, already written for a
/// human — the UI shows [message] verbatim. The original error is kept
/// in [cause] for logging only, never rendered. Mirrors
/// `SessionException`'s shape.
class ProfileException implements Exception {
  const ProfileException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'ProfileException: $message${cause == null ? '' : ' (cause: $cause)'}';
}
