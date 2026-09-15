import 'package:flutter/widgets.dart';

import '../../../../core/widgets/confirm_dialog.dart';
import '../../domain/book_note.dart';
import '../../domain/collections.dart';
import '../../domain/library_book.dart';

/// The "are you sure?" wording for every removal that can't be undone — in
/// one place so the add tab's `remove`/`delete` commands and the library's
/// "+" panel ask exactly the same question for the same action.

/// Confirms unmaking a shelf, tag or series — everything filed under it
/// loses it.
Future<bool> confirmUnmake(BuildContext context, UnmakeCollection removal) {
  final (noun, consequence) = switch (removal.kind) {
    CollectionKind.shelves => (
      'shelf',
      removal.bookCount == 0
          ? "it's empty, so no books move."
          : removal.bookCount == 1
          ? 'the 1 book on it goes back to its own shelf, progress kept.'
          : 'the ${removal.bookCount} books on it go back to their own '
                'shelves, progress kept.',
    ),
    CollectionKind.tags => ('tag', 'it comes off every book it was on.'),
    CollectionKind.series => (
      'series',
      removal.bookCount == 0
          ? 'no books are filed under it.'
          : removal.bookCount == 1
          ? 'the 1 book in it leaves the series, number and all.'
          : 'the ${removal.bookCount} books in it leave the series, numbers '
                'and all.',
    ),
  };
  return showConfirmDialog(
    context,
    title: 'remove $noun "${removal.name}"?',
    message: "$consequence this can't be undone.",
    confirmLabel: 'remove',
    routeName: 'confirm_remove_collection',
  );
}

/// Confirms removing one of [entry]'s comments, quoting it so the reader
/// sees exactly which.
Future<bool> confirmRemoveComment(
  BuildContext context,
  LibraryBook entry,
  BookComment comment,
) {
  final body = comment.body.trim();
  final quoted = body.length > 160 ? '${body.substring(0, 157)}…' : body;
  return showConfirmDialog(
    context,
    title: 'remove this comment from ${entry.book.title}?',
    message: '"$quoted"',
    confirmLabel: 'remove',
    routeName: 'confirm_remove_comment',
  );
}

/// Confirms removing [entry] from the library — `delete <book>` and the
/// "+" panel's books tab.
Future<bool> confirmRemoveBook(BuildContext context, LibraryBook entry) {
  return showConfirmDialog(
    context,
    title: 'delete ${entry.book.title}?',
    message:
        'this removes it from your library along with its tags, comments '
        "and reading history. this can't be undone.",
    confirmLabel: 'delete',
    routeName: 'confirm_delete',
  );
}
