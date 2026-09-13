import 'package:supabase_flutter/supabase_flutter.dart';

import '../../library/data/supabase_guard.dart';
import '../../library/domain/user_book.dart';

/// One matched import row, ready for `replace_library`.
class ImportedBook {
  const ImportedBook({
    required this.bookId,
    required this.status,
    required this.currentPage,
    this.rating,
    this.startedAt,
    this.finishedAt,
    this.tags = const [],
    this.comments = const [],
  });

  final String bookId;
  final ReadingStatus status;
  final int currentPage;
  final double? rating;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final List<String> tags;
  final List<String> comments;

  Map<String, Object?> toJson() => {
    'book_id': bookId,
    'status': status.wireValue,
    'current_page': currentPage,
    'rating': rating,
    'started_at': startedAt?.toUtc().toIso8601String(),
    'finished_at': finishedAt?.toUtc().toIso8601String(),
    'tags': tags,
    'comments': comments,
  };
}

/// The one write the Goodreads import makes: `replace_library`, which swaps
/// the caller's whole library for [ImportedBook]s in a single transaction.
class LibraryTransferRepository {
  LibraryTransferRepository({SupabaseClient? client})
    : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  /// Returns how many books the new library holds.
  Future<int> replaceLibrary(List<ImportedBook> books) {
    return runSupabase(
      () async {
        final count = await _client.rpc<int>(
          'replace_library',
          params: {
            'p_books': [for (final book in books) book.toJson()],
          },
        );
        return count;
      },
      friendlyMessage: "We couldn't replace your library — try again.",
      // A few thousand rows in one transaction can take a while.
      timeout: const Duration(seconds: 60),
    );
  }
}
