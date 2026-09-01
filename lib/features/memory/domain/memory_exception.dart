/// A failure from a [MemoryRepository] call, already written for a
/// human — the UI shows [message] verbatim. Mirrors
/// `AiCommandException`/`OnboardingException`'s shape: this feature's
/// failure surface is small enough (offline, a rejected write) that it
/// doesn't need `LibraryException`'s sealed hierarchy of subtypes.
class MemoryException implements Exception {
  const MemoryException(this.message, {this.cause});

  final String message;

  /// The underlying error, kept for logs only — never rendered.
  final Object? cause;

  @override
  String toString() =>
      'MemoryException: $message${cause == null ? '' : ' (cause: $cause)'}';
}
