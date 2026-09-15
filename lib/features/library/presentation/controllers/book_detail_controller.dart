import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../data/book_notes_repository.dart';
import '../../domain/book.dart';
import '../../domain/book_details_service.dart';
import '../../domain/book_edition.dart';
import '../../domain/book_note.dart';
import '../../domain/collections.dart';
import '../../domain/library_exception.dart';
import 'library_controller.dart';

/// One independently-loading section of the detail page: its data, whether
/// it is loading, and the message from its last failed load.
///
/// Sections fail independently on purpose — Google Books being down must
/// not blank a reader's own tags and comments, and a slow editions search
/// must not hold up the blurb.
class DetailSection<T> {
  const DetailSection({this.data, this.isLoading = false, this.error});

  final T? data;
  final bool isLoading;
  final String? error;

  bool get hasData => data != null;
}

/// State for one open book detail page: the catalogue info, editions,
/// tags and comments that page shows *beyond* the shelf row itself.
///
/// The shelf row (status, progress, rating, owned edition) is deliberately
/// not held here — it stays in [LibraryController], the one mutation point
/// for shelf state, and the page reads it from there by id. This class
/// owns only what exists nowhere else in the app's memory: per-page
/// fetches that are discarded when the page closes.
///
/// Tag and comment mutations are optimistic, the same convention as every
/// `LibraryController` command: the list changes and notifies at once,
/// then persists, rolling back (and returning the failure) if the write
/// is refused.
class BookDetailController extends ChangeNotifier {
  BookDetailController({
    required this.userBookId,
    required Book book,
    required this.details,
    required this.notes,
    required this.findTag,
    this.onTagsChanged,
  }) : _book = DetailSection(data: book);

  final String userBookId;
  final BookDetailsService details;
  final BookNotesRepository notes;

  /// Resolves a typed tag name to one of the reader's own tags —
  /// `LibraryController.findTag` in the app. The tag field only *applies*
  /// tags; making one is `make tag` or the library's "+" panel, so an
  /// unknown name is refused here rather than created.
  final ReaderTag? Function(String name) findTag;

  /// Called once a tag add or removal has actually persisted —
  /// `LibraryController.notifyTagsChanged` in the app, so tag counts
  /// elsewhere stay current. Never called for a write that rolled back.
  final VoidCallback? onTagsChanged;

  /// Starts as the shelf's own copy of the book, so the page has a title,
  /// cover and (often) a blurb from the very first frame; [load] replaces
  /// it with the detailed row.
  DetailSection<Book> _book;
  DetailSection<List<BookEdition>> _editions = const DetailSection();
  DetailSection<List<BookTag>> _tags = const DetailSection();
  DetailSection<List<BookComment>> _comments = const DetailSection();

  DetailSection<Book> get book => _book;
  DetailSection<List<BookEdition>> get editions => _editions;
  DetailSection<List<BookTag>> get tags => _tags;
  DetailSection<List<BookComment>> get comments => _comments;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Notifies unless the page already closed — every load here is async
  /// and outlives a reader who backs out quickly.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Loads all four sections concurrently. Never throws; each section
  /// records its own failure.
  Future<void> load() => Future.wait([
    loadDetails(),
    loadTags(),
    loadComments(),
    // Editions search by the book's title/author, which the shelf's copy
    // already has — no need to wait for the detailed row first.
    loadEditions(),
  ]);

  Future<void> loadDetails() async {
    final current = _book.data!;
    _book = DetailSection(data: current, isLoading: true);
    _notify();
    try {
      _book = DetailSection(data: await details.detailsFor(current));
    } on LibraryException catch (error) {
      // The shelf's copy is still perfectly renderable; keep it and say
      // what's missing rather than replacing the section with an error.
      _book = DetailSection(data: current, error: error.message);
      AppLogger.info('BookDetailController', 'Details failed: $error');
    }
    _notify();
  }

  Future<void> loadEditions() async {
    _editions = DetailSection(data: _editions.data, isLoading: true);
    _notify();
    try {
      _editions = DetailSection(data: await details.editionsFor(_book.data!));
    } on LibraryException catch (error) {
      _editions = DetailSection(data: _editions.data, error: error.message);
      AppLogger.info('BookDetailController', 'Editions failed: $error');
    }
    _notify();
  }

  Future<void> loadTags() async {
    _tags = DetailSection(data: _tags.data, isLoading: true);
    _notify();
    try {
      _tags = DetailSection(data: await notes.fetchTags(userBookId));
    } on LibraryException catch (error) {
      _tags = DetailSection(data: _tags.data, error: error.message);
    }
    _notify();
  }

  Future<void> loadComments() async {
    _comments = DetailSection(data: _comments.data, isLoading: true);
    _notify();
    try {
      _comments = DetailSection(data: await notes.fetchComments(userBookId));
    } on LibraryException catch (error) {
      _comments = DetailSection(data: _comments.data, error: error.message);
    }
    _notify();
  }

  /// Applies the reader's tag named [raw] to this book. Refuses a tag that
  /// hasn't been made yet, and one the book already has (ignoring case),
  /// before any I/O.
  Future<LibraryActionResult> addTag(String raw) async {
    final String tag;
    try {
      tag = BookNotesRepository.validateTag(raw);
    } on LibraryException catch (error) {
      return LibraryActionResult.failure(error.message);
    }
    final resolved = findTag(tag);
    if (resolved == null) {
      return LibraryActionResult.failure(
        LibraryController.unknownTagMessage(tag),
      );
    }
    final existing = _tags.data ?? const <BookTag>[];
    if (existing.any(
      (t) => BookTag.normalize(t.tag) == BookTag.normalize(tag),
    )) {
      return LibraryActionResult.failure('This book is already tagged "$tag".');
    }

    final placeholder = BookTag(
      id: _pendingId(),
      userBookId: userBookId,
      tag: resolved.name,
      createdAt: DateTime.now(),
    );
    _tags = DetailSection(data: [...existing, placeholder]);
    _notify();

    try {
      final saved = await notes.addTag(userBookId, resolved);
      _tags = DetailSection(
        data: [
          for (final t in _tags.data ?? const <BookTag>[])
            t.id == placeholder.id ? saved : t,
        ],
      );
      _notify();
      onTagsChanged?.call();
      return LibraryActionResult.success('Tagged ${saved.tag}');
    } on LibraryException catch (error) {
      _tags = DetailSection(
        data: [
          for (final t in _tags.data ?? const <BookTag>[])
            if (t.id != placeholder.id) t,
        ],
      );
      _notify();
      return LibraryActionResult.failure(error.message);
    }
  }

  Future<LibraryActionResult> removeTag(String tagId) async {
    final before = _tags.data ?? const <BookTag>[];
    if (_isPending(tagId)) {
      // Still being saved — there is no row to delete yet.
      return const LibraryActionResult.failure('That tag is still saving.');
    }
    final index = before.indexWhere((t) => t.id == tagId);
    if (index == -1) return const LibraryActionResult.success();
    final removed = before[index];
    _tags = DetailSection(
      data: [
        for (final t in before)
          if (t.id != tagId) t,
      ],
    );
    _notify();
    try {
      await notes.removeTag(tagId);
      onTagsChanged?.call();
      return const LibraryActionResult.success();
    } on LibraryException catch (error) {
      _tags = DetailSection(
        data: _reinserted(_tags.data ?? const [], removed, index),
      );
      _notify();
      return LibraryActionResult.failure(error.message);
    }
  }

  Future<LibraryActionResult> addComment(String raw) async {
    final String body;
    try {
      body = BookNotesRepository.validateComment(raw);
    } on LibraryException catch (error) {
      return LibraryActionResult.failure(error.message);
    }

    final placeholder = BookComment(
      id: _pendingId(),
      userBookId: userBookId,
      body: body,
      createdAt: DateTime.now(),
    );
    _comments = DetailSection(data: [...?_comments.data, placeholder]);
    _notify();

    try {
      final saved = await notes.addComment(userBookId, body);
      _comments = DetailSection(
        data: [
          for (final c in _comments.data ?? const <BookComment>[])
            c.id == placeholder.id ? saved : c,
        ],
      );
      _notify();
      return const LibraryActionResult.success('Comment saved');
    } on LibraryException catch (error) {
      _comments = DetailSection(
        data: [
          for (final c in _comments.data ?? const <BookComment>[])
            if (c.id != placeholder.id) c,
        ],
      );
      _notify();
      return LibraryActionResult.failure(error.message);
    }
  }

  Future<LibraryActionResult> editComment(String commentId, String raw) async {
    final String body;
    try {
      body = BookNotesRepository.validateComment(raw);
    } on LibraryException catch (error) {
      return LibraryActionResult.failure(error.message);
    }
    if (_isPending(commentId)) {
      return const LibraryActionResult.failure('That comment is still saving.');
    }

    final before = _comments.data ?? const <BookComment>[];
    final original = before.where((c) => c.id == commentId).firstOrNull;
    if (original == null) {
      return const LibraryActionResult.failure('That comment is gone.');
    }
    if (original.body == body) return const LibraryActionResult.success();

    _comments = DetailSection(
      data: [
        for (final c in before)
          c.id == commentId
              ? c.copyWith(body: body, updatedAt: DateTime.now())
              : c,
      ],
    );
    _notify();

    try {
      final saved = await notes.updateComment(commentId, body);
      _comments = DetailSection(
        data: [
          for (final c in _comments.data ?? const <BookComment>[])
            c.id == commentId ? saved : c,
        ],
      );
      _notify();
      return const LibraryActionResult.success('Comment updated');
    } on LibraryException catch (error) {
      // Only this comment goes back — anything else that changed while the
      // edit was out (a new comment saved) stays.
      _comments = DetailSection(
        data: [
          for (final c in _comments.data ?? const <BookComment>[])
            c.id == commentId ? original : c,
        ],
      );
      _notify();
      return LibraryActionResult.failure(error.message);
    }
  }

  Future<LibraryActionResult> deleteComment(String commentId) async {
    if (_isPending(commentId)) {
      return const LibraryActionResult.failure('That comment is still saving.');
    }
    final before = _comments.data ?? const <BookComment>[];
    final index = before.indexWhere((c) => c.id == commentId);
    if (index == -1) return const LibraryActionResult.success();
    final removed = before[index];
    _comments = DetailSection(
      data: [
        for (final c in before)
          if (c.id != commentId) c,
      ],
    );
    _notify();
    try {
      await notes.deleteComment(commentId);
      return const LibraryActionResult.success('Comment deleted');
    } on LibraryException catch (error) {
      _comments = DetailSection(
        data: _reinserted(_comments.data ?? const [], removed, index),
      );
      _notify();
      return LibraryActionResult.failure(error.message);
    }
  }

  /// [current] with [item] put back at [index] (or the end, if the list
  /// has since shrunk) — the rollback for a removal that failed.
  ///
  /// Rolls back just that one item rather than restoring a snapshot of the
  /// whole list taken before the removal: a snapshot also erased anything
  /// that landed while the removal was out, such as a tag added a moment
  /// later that really did save.
  static List<T> _reinserted<T>(List<T> current, T item, int index) {
    if (current.contains(item)) return current;
    return [...current]..insert(index.clamp(0, current.length), item);
  }

  static const _pendingPrefix = '_pending_';
  static String _pendingId() =>
      '$_pendingPrefix${DateTime.now().microsecondsSinceEpoch}';

  /// Whether [id] is an optimistic placeholder that hasn't been written
  /// yet — the page renders those faded and without delete/edit actions.
  static bool isPending(String id) => id.startsWith(_pendingPrefix);
  static bool _isPending(String id) => isPending(id);
}
