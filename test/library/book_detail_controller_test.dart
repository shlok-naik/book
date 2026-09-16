import 'dart:async';

import 'package:book/features/library/data/book_details_repository.dart';
import 'package:book/features/library/data/book_notes_repository.dart';
import 'package:book/features/library/data/google_books_api_client.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/book_details_service.dart';
import 'package:book/features/library/domain/book_edition.dart';
import 'package:book/features/library/domain/book_note.dart';
import 'package:book/features/library/domain/collections.dart';
import 'package:book/features/library/domain/library_exception.dart';
import 'package:book/features/library/presentation/controllers/book_detail_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _dune = Book(
  id: 'book-1',
  googleBooksId: 'gb-dune',
  title: 'Dune',
  author: 'Frank Herbert',
);

class FakeDetailsService extends BookDetailsService {
  FakeDetailsService()
    : super(
        cache: BookDetailsRepository(),
        googleBooks: GoogleBooksApiClient(
          client: MockClient((_) async => http.Response('unused', 500)),
        ),
      );

  LibraryException? detailsFailure;
  LibraryException? editionsFailure;

  @override
  Future<Book> detailsFor(Book book) async {
    if (detailsFailure != null) throw detailsFailure!;
    return Book(
      id: book.id,
      googleBooksId: book.googleBooksId,
      title: book.title,
      author: book.author,
      publisher: 'Ace',
      detailsFetchedAt: DateTime.utc(2026),
    );
  }

  @override
  Future<List<BookEdition>> editionsFor(Book book) async {
    if (editionsFailure != null) throw editionsFailure!;
    return const [
      BookEdition(
        id: 'e1',
        googleBooksId: 'g1',
        title: 'Dune',
        author: 'Frank Herbert',
        format: EditionFormat.ebook,
      ),
    ];
  }
}

class FakeNotes extends BookNotesRepository {
  final tags = <BookTag>[];
  final comments = <BookComment>[];
  LibraryException? failure;
  LibraryException? loadFailure;

  /// When set, writes wait on this — lets a test look at the optimistic
  /// state before the write resolves.
  Completer<void>? gate;

  Future<void> _write() async {
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
  }

  @override
  Future<List<BookTag>> fetchTags(String userBookId) async {
    if (loadFailure != null) throw loadFailure!;
    return List.of(tags);
  }

  @override
  Future<List<BookComment>> fetchComments(String userBookId) async {
    if (loadFailure != null) throw loadFailure!;
    return List.of(comments);
  }

  @override
  Future<BookTag> addTag(String userBookId, ReaderTag tag) async {
    await _write();
    final saved = BookTag(
      id: 'tag-${tags.length}',
      userBookId: userBookId,
      tag: tag.name,
      createdAt: DateTime(2026),
    );
    tags.add(saved);
    return saved;
  }

  /// Fails only [removeTag] — so an add can succeed while a removal fails.
  LibraryException? removeFailure;

  @override
  Future<void> removeTag(String tagId) async {
    await _write();
    if (removeFailure != null) throw removeFailure!;
  }

  @override
  Future<BookComment> addComment(String userBookId, String body) async {
    await _write();
    return BookComment(
      id: 'comment-${comments.length}',
      userBookId: userBookId,
      body: body,
      createdAt: DateTime(2026),
    );
  }

  @override
  Future<BookComment> updateComment(String commentId, String body) async {
    await _write();
    return BookComment(
      id: commentId,
      userBookId: 'u1',
      body: body,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026, 2),
    );
  }

  @override
  Future<void> deleteComment(String commentId) => _write();
}

/// The reader's made tags — the only names the tag field will apply.
const _madeTags = [
  ReaderTag(id: 'reader-tag-sci-fi', name: 'sci-fi'),
  ReaderTag(id: 'reader-tag-cosy', name: 'cosy'),
];

ReaderTag? _findMadeTag(String name) {
  for (final tag in _madeTags) {
    if (tag.name.toLowerCase() == name.trim().toLowerCase()) return tag;
  }
  return null;
}

void main() {
  late FakeDetailsService details;
  late FakeNotes notes;
  late BookDetailController controller;

  setUp(() {
    details = FakeDetailsService();
    notes = FakeNotes();
    controller = BookDetailController(
      userBookId: 'u1',
      book: _dune,
      details: details,
      notes: notes,
      findTag: _findMadeTag,
    );
  });

  tearDown(() => controller.dispose());

  test('starts with the shelf copy so the page has a title at once', () {
    expect(controller.book.data!.title, 'Dune');
    expect(controller.editions.hasData, isFalse);
  });

  test('load fills every section', () async {
    notes.tags.add(
      BookTag(
        id: 't',
        userBookId: 'u1',
        tag: 'sci-fi',
        createdAt: DateTime(2026),
      ),
    );

    await controller.load();

    expect(controller.book.data!.publisher, 'Ace');
    expect(controller.editions.data!.single.id, 'e1');
    expect(controller.tags.data!.single.tag, 'sci-fi');
    expect(controller.comments.data, isEmpty);
  });

  test('sections fail independently, keeping what they had', () async {
    details.detailsFailure = const NetworkException('Google is down');
    details.editionsFailure = const NetworkException('Google is down');

    await controller.load();

    expect(controller.book.error, 'Google is down');
    expect(controller.book.data!.title, 'Dune', reason: 'shelf copy kept');
    expect(controller.editions.error, 'Google is down');
    expect(controller.tags.error, isNull);
    expect(controller.tags.data, isEmpty);
  });

  test('a retry clears a section error once it succeeds', () async {
    details.editionsFailure = const NetworkException('down');
    await controller.loadEditions();
    expect(controller.editions.error, isNotNull);

    details.editionsFailure = null;
    await controller.loadEditions();
    expect(controller.editions.error, isNull);
    expect(controller.editions.data, hasLength(1));
  });

  group('tags', () {
    test('adds optimistically, then swaps in the stored row', () async {
      await controller.load();
      notes.gate = Completer<void>();

      final pending = controller.addTag('  sci-fi ');
      expect(controller.tags.data!.single.tag, 'sci-fi');
      expect(
        BookDetailController.isPending(controller.tags.data!.single.id),
        isTrue,
      );

      notes.gate!.complete();
      final result = await pending;

      expect(result.success, isTrue);
      expect(controller.tags.data!.single.id, 'tag-0');
    });

    test('refuses a duplicate in any case before writing', () async {
      await controller.load();
      await controller.addTag('Sci-Fi');

      final result = await controller.addTag('sci-fi');

      expect(result.success, isFalse);
      expect(result.message, 'Already tagged "sci-fi".');
      expect(notes.tags, hasLength(1));
    });

    test('rolls back a failed add', () async {
      await controller.load();
      notes.failure = const NetworkException("You're offline");

      final result = await controller.addTag('sci-fi');

      expect(result.success, isFalse);
      expect(result.message, "You're offline");
      expect(controller.tags.data, isEmpty);
    });

    test('rejects an empty tag without writing', () async {
      final result = await controller.addTag('   ');
      expect(result.success, isFalse);
      expect(result.message, 'Name the tag first.');
    });

    test(
      'refuses a tag that was never made, rather than creating it',
      () async {
        await controller.load();

        final result = await controller.addTag('space opera');

        expect(result.success, isFalse);
        expect(
          result.message,
          'No tag "space opera". Try: make tag space opera',
        );
        expect(controller.tags.data, isEmpty);
        expect(notes.tags, isEmpty);
      },
    );

    test('rolls back a failed remove', () async {
      await controller.addTag('sci-fi');
      final id = controller.tags.data!.single.id;
      notes.failure = const NetworkException("You're offline");

      final result = await controller.removeTag(id);

      expect(result.success, isFalse);
      expect(controller.tags.data!.single.id, id);
    });

    // Regression: a failed removal used to restore the whole list as it was
    // before, erasing a tag that was added — and saved — in the meantime.
    test('a failed remove puts back only that tag, keeping one added while '
        'it was out', () async {
      await controller.addTag('sci-fi');
      final id = controller.tags.data!.single.id;
      final gate = notes.gate = Completer<void>();
      notes.removeFailure = const NetworkException("You're offline");

      final removal = controller.removeTag(id);
      final add = controller.addTag('cosy');
      gate.complete();
      await Future.wait([removal, add]);

      expect(
        controller.tags.data!.map((t) => t.tag),
        unorderedEquals(['sci-fi', 'cosy']),
      );
      expect(
        controller.tags.data!.any((t) => BookDetailController.isPending(t.id)),
        isFalse,
      );
    });
  });

  group('comments', () {
    test('add, edit and delete', () async {
      await controller.load();

      await controller.addComment('slow start');
      final id = controller.comments.data!.single.id;

      final edited = await controller.editComment(id, 'slow start, great end');
      expect(edited.success, isTrue);
      expect(controller.comments.data!.single.body, 'slow start, great end');
      expect(controller.comments.data!.single.isEdited, isTrue);

      final deleted = await controller.deleteComment(id);
      expect(deleted.success, isTrue);
      expect(controller.comments.data, isEmpty);
    });

    test('an unchanged edit is a no-op success', () async {
      await controller.addComment('same');
      final id = controller.comments.data!.single.id;
      notes.failure = const NetworkException('would fail if called');

      expect((await controller.editComment(id, ' same ')).success, isTrue);
    });

    test('rolls back a failed edit and a failed delete', () async {
      await controller.addComment('original');
      final id = controller.comments.data!.single.id;
      notes.failure = const NetworkException("You're offline");

      expect((await controller.editComment(id, 'changed')).success, isFalse);
      expect(controller.comments.data!.single.body, 'original');

      expect((await controller.deleteComment(id)).success, isFalse);
      expect(controller.comments.data, hasLength(1));
    });

    test('rejects an overlong comment without writing', () async {
      final result = await controller.addComment('x' * 1001);
      expect(result.success, isFalse);
      expect(result.message, 'Max 1000 characters.');
      expect(controller.comments.data, isNull);
    });
  });

  test('a load that lands after the page closed does not throw', () async {
    final gate = Completer<void>();
    final slow = _SlowDetails(gate.future);
    final early = BookDetailController(
      userBookId: 'u1',
      book: _dune,
      details: slow,
      notes: notes,
      findTag: _findMadeTag,
    );
    final loading = early.loadDetails();
    early.dispose();
    gate.complete();
    await loading;
  });
}

class _SlowDetails extends FakeDetailsService {
  _SlowDetails(this.wait);

  final Future<void> wait;

  @override
  Future<Book> detailsFor(Book book) async {
    await wait;
    return book;
  }
}
