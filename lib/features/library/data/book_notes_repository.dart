import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/book_note.dart';
import '../domain/library_exception.dart';
import 'supabase_guard.dart';

/// Reads and writes the reader's own tags and comments on a shelf row —
/// the `book_tags` and `book_comments` tables. Private per reader: like
/// every other per-reader table, `user_id` is never sent from here; the
/// column default and RLS own it, and RLS also refuses a note attached to
/// someone else's `user_books` id.
///
/// Failures come back as [LibraryException]s through [runSupabase], same as
/// `UserBookRepository` — tags and comments live on the library feature's
/// shelf rows, so they share its error vocabulary rather than inventing a
/// third one.
class BookNotesRepository {
  BookNotesRepository({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  /// Postgres' unique_violation — a duplicate tag on the same book.
  static const _uniqueViolation = '23505';

  /// Every tag on every book on the reader's shelf, in one query — what
  /// library search and the CSV export use. Oldest first within a book.
  Future<List<BookTag>> fetchAllTags() {
    return runSupabase(() async {
      final rows = await _client.from('book_tags').select().order('created_at');
      return [for (final row in rows) ?BookTag.fromRow(row)];
    }, friendlyMessage: "We couldn't load your tags.");
  }

  /// Every comment on every book on the reader's shelf — for the CSV
  /// export. Oldest first.
  Future<List<BookComment>> fetchAllComments() {
    return runSupabase(() async {
      final rows = await _client
          .from('book_comments')
          .select()
          .order('created_at');
      return [for (final row in rows) ?BookComment.fromRow(row)];
    }, friendlyMessage: "We couldn't load your comments.");
  }

  Future<List<BookTag>> fetchTags(String userBookId) {
    return runSupabase(() async {
      final rows = await _client
          .from('book_tags')
          .select()
          .eq('user_book_id', userBookId)
          .order('created_at');
      return [for (final row in rows) ?BookTag.fromRow(row)];
    }, friendlyMessage: "We couldn't load this book's tags.");
  }

  /// Adds [tag] to [userBookId] and returns the stored row.
  ///
  /// Validates before any I/O (see [validateTag]). A tag the book already
  /// has — in any capitalisation — fails with a message saying so rather
  /// than a generic "couldn't save", since the unique index is the
  /// authority on that and a race past a client-side check is possible.
  Future<BookTag> addTag(String userBookId, String tag) async {
    final clean = validateTag(tag);
    try {
      return await runSupabase(() async {
        final row = await _client
            .from('book_tags')
            .insert({'user_book_id': userBookId, 'tag': clean})
            .select()
            .single();
        final parsed = BookTag.fromRow(row);
        if (parsed == null) {
          throw RemoteDataException(
            "We couldn't save that tag.",
            cause: 'unparseable book_tags row: $row',
          );
        }
        return parsed;
      }, friendlyMessage: "We couldn't save that tag.");
    } on RemoteDataException catch (error) {
      final cause = error.cause;
      if (cause is PostgrestException && cause.code == _uniqueViolation) {
        throw InvalidInputException('This book is already tagged "$clean".');
      }
      rethrow;
    }
  }

  Future<void> removeTag(String tagId) {
    return runSupabase<void>(() async {
      await _client.from('book_tags').delete().eq('id', tagId);
    }, friendlyMessage: "We couldn't remove that tag.");
  }

  Future<List<BookComment>> fetchComments(String userBookId) {
    return runSupabase(() async {
      final rows = await _client
          .from('book_comments')
          .select()
          .eq('user_book_id', userBookId)
          .order('created_at');
      return [for (final row in rows) ?BookComment.fromRow(row)];
    }, friendlyMessage: "We couldn't load this book's comments.");
  }

  Future<BookComment> addComment(String userBookId, String body) async {
    final clean = validateComment(body);
    return runSupabase(() async {
      final row = await _client
          .from('book_comments')
          .insert({'user_book_id': userBookId, 'body': clean})
          .select()
          .single();
      return _parseComment(row, "We couldn't save that comment.");
    }, friendlyMessage: "We couldn't save that comment.");
  }

  Future<BookComment> updateComment(String commentId, String body) async {
    final clean = validateComment(body);
    return runSupabase(() async {
      final row = await _client
          .from('book_comments')
          // `updated_at` is set by the `touch_updated_at` trigger.
          .update({'body': clean})
          .eq('id', commentId)
          .select()
          .single();
      return _parseComment(row, "We couldn't update that comment.");
    }, friendlyMessage: "We couldn't update that comment.");
  }

  Future<void> deleteComment(String commentId) {
    return runSupabase<void>(() async {
      await _client.from('book_comments').delete().eq('id', commentId);
    }, friendlyMessage: "We couldn't delete that comment.");
  }

  BookComment _parseComment(Map<String, dynamic> row, String message) {
    final parsed = BookComment.fromRow(row);
    if (parsed == null) {
      throw RemoteDataException(message, cause: 'unparseable row: $row');
    }
    return parsed;
  }

  /// Trims [tag] and checks it against the `book_tags` constraint. Tags
  /// are labels, not sentences — one line, at most [BookTag.maxLength].
  /// Throws [InvalidInputException]; returns the cleaned tag.
  static String validateTag(String tag) {
    final clean = tag.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) throw const InvalidInputException('Type a tag first.');
    if (clean.length > BookTag.maxLength) {
      throw const InvalidInputException(
        'Tags can be at most ${BookTag.maxLength} characters.',
      );
    }
    return clean;
  }

  /// Trims [body] and checks it against the `book_comments` constraint.
  static String validateComment(String body) {
    final clean = body.trim();
    if (clean.isEmpty) {
      throw const InvalidInputException('Write a comment first.');
    }
    if (clean.length > BookComment.maxLength) {
      throw const InvalidInputException(
        'Comments can be at most ${BookComment.maxLength} characters.',
      );
    }
    return clean;
  }
}
