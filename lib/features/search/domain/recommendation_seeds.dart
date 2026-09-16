import '../../library/domain/library_book.dart';
import '../../library/domain/user_book.dart';
import '../../streaks/domain/reading_stats.dart';
import 'reading_taste.dart';

/// One row of recommendations on the search tab: what it's called and the
/// Google Books query that fills it.
class RecommendationSeed {
  const RecommendationSeed({required this.label, required this.query});

  final String label;
  final String query;

  @override
  bool operator ==(Object other) =>
      other is RecommendationSeed &&
      other.label == label &&
      other.query == query;

  @override
  int get hashCode => Object.hash(label, query);
}

/// Picks the recommendation rows from the reader's own shelf — no AI, just
/// what they've read, so every reader gets them for free:
///
/// * **more by (author)** — the author of the book they're reading now, or
///   else the one they finished most recently;
/// * **more in (genre)** — their most-read genre among finished books
///   ([ReadingStats.genreOf]), when there is one;
/// * **(taste) for you** — one row per kind of book the reader said they
///   like ([ReadingTaste], from onboarding or settings), up to three, right
///   after the author row;
/// * **classics to start with** — only when there's nothing else to go on.
abstract final class RecommendationSeeds {
  static const maxTasteRows = 3;

  static List<RecommendationSeed> from(
    List<LibraryBook> books, {
    List<ReadingTaste> tastes = const [],
  }) {
    final seeds = <RecommendationSeed>[];

    final author = _anchorAuthor(books);
    if (author != null) {
      seeds.add(
        RecommendationSeed(
          label: 'more by $author',
          query: 'inauthor:"$author"',
        ),
      );
    }

    for (final taste in tastes.take(maxTasteRows)) {
      seeds.add(
        RecommendationSeed(
          label: '${taste.label} for you',
          query: 'subject:"${taste.subject}"',
        ),
      );
    }

    final genre = _topGenre(books);
    final covered = {for (final taste in tastes) taste.subject.toLowerCase()};
    if (genre != null && !covered.contains(genre.toLowerCase())) {
      seeds.add(
        RecommendationSeed(
          label: 'more in ${genre.toLowerCase()}',
          query: 'subject:"$genre"',
        ),
      );
    }

    if (seeds.isEmpty) {
      seeds.add(
        const RecommendationSeed(
          label: 'classics to start with',
          query: 'subject:"classics"',
        ),
      );
    }
    return seeds;
  }

  /// [books] come most recently updated first — the shelf's own natural
  /// order — so the first match is the latest.
  static String? _anchorAuthor(List<LibraryBook> books) {
    LibraryBook? latest(bool Function(LibraryBook) test) {
      for (final entry in books) {
        if (test(entry)) return entry;
      }
      return null;
    }

    final anchor =
        latest((e) => e.status == ReadingStatus.reading) ??
        latest((e) => e.status == ReadingStatus.finished);
    final author = anchor?.book.author.split(',').first.trim();
    return author == null || author.isEmpty ? null : author;
  }

  static String? _topGenre(List<LibraryBook> books) {
    final counts = <String, int>{};
    for (final entry in books) {
      if (entry.status != ReadingStatus.finished) continue;
      final genres = {
        for (final category in entry.book.categories)
          ?ReadingStats.genreOf(category),
      };
      for (final genre in genres) {
        counts[genre] = (counts[genre] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return null;
    return (counts.entries.toList()..sort((a, b) => b.value - a.value))
        .first
        .key;
  }
}
