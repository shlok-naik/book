/// Failures the library feature can surface.
///
/// Every subtype carries a [message] that is written for a human — the
/// UI shows it verbatim, so nothing here should contain a stack trace,
/// an HTTP body, or a Postgres error code. The original failure is kept
/// in [cause] for logging/debugging only.
sealed class LibraryException implements Exception {
  const LibraryException(this.message, {this.cause});

  /// User-facing, already-friendly text. Safe to render directly.
  final String message;

  /// The underlying error (SocketException, PostgrestException, …).
  /// Never shown to the user.
  final Object? cause;

  @override
  String toString() =>
      '$runtimeType: $message${cause == null ? '' : ' (cause: $cause)'}';
}

/// The user's input failed validation before any I/O happened —
/// an empty search, a non-numeric page, a page out of range.
class InvalidInputException extends LibraryException {
  const InvalidInputException(super.message);
}

/// Neither the Supabase cache nor Google Books knew about the book.
class BookNotFoundException extends LibraryException {
  const BookNotFoundException(super.message, {super.cause});
}

/// The device is offline, a request timed out, or a remote service
/// answered with a server-side error. Retrying later may work.
class NetworkException extends LibraryException {
  const NetworkException(super.message, {super.cause});
}

/// A remote service answered, but with something we could not parse or
/// accept — malformed JSON, a row missing required columns, a rejected
/// write. Retrying the same call will not help.
class RemoteDataException extends LibraryException {
  const RemoteDataException(super.message, {super.cause});
}
