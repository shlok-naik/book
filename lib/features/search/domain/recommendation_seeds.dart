import '../../library/domain/library_book.dart';
import '../../library/domain/user_book.dart';
import '../../streaks/domain/reading_stats.dart';
import 'reading_taste.dart';

/// Where a recommendation row's books come from.
enum SeedSource {
  /// A Google Books query.
  catalogue,

  /// What other cactus readers have on their shelves (`popular_books`).
  readers,
}

/// One row of recommendations on the search tab: what it's called and how
/// it's filled.
class RecommendationSeed {
  const RecommendationSeed({
    required this.label,
    this.query = '',
    this.source = SeedSource.catalogue,
    this.orderBy,
    this.byPopularity = false,
    this.maxPages,
  });

  final String label;

  /// The Google Books query, for [SeedSource.catalogue].
  final String query;
  final SeedSource source;

  /// Google's own `orderBy` — only `newest` means anything beyond its
  /// default relevance.
  final String? orderBy;

  /// Re-sort the results by how many ratings each has on Google Books —
  /// the closest thing it offers to "most popular".
  final bool byPopularity;

  /// Keep only books this short.
  final int? maxPages;

  @override
  bool operator ==(Object other) =>
      other is RecommendationSeed &&
      other.label == label &&
      other.query == query &&
      other.source == source &&
      other.orderBy == orderBy &&
      other.byPopularity == byPopularity &&
      other.maxPages == maxPages;

  @override
  int get hashCode =>
      Object.hash(label, query, source, orderBy, byPopularity, maxPages);
}

/// Picks the search tab's rows, Goodreads-discover style. Personal rows
/// first, then the same browsing rows for everyone:
///
/// * **our readers read** — what's on the most cactus shelves;
/// * **more by (author)** — the book being read, else the latest finished;
/// * **(taste) for you** — up to three of the reader's [ReadingTaste]s;
/// * **more in (genre)** — their most-read finished genre, unless a taste
///   already covers it;
/// * [browse]: popular right now, new releases, timeless classics, short
///   reads, award winners and nonfiction worth reading.
abstract final class RecommendationSeeds {
  static const maxTasteRows = 3;

  /// The rows every reader gets, after their own.
  static const browse = [
    RecommendationSeed(
      label: 'popular right now',
      query: 'subject:"fiction"',
      byPopularity: true,
    ),
    RecommendationSeed(
      label: 'new releases',
      query: 'subject:"fiction"',
      orderBy: 'newest',
    ),
    RecommendationSeed(
      label: 'timeless classics',
      query: 'subject:"classics"',
      byPopularity: true,
    ),
    RecommendationSeed(
      label: 'short reads',
      query: 'subject:"fiction"',
      byPopularity: true,
      maxPages: 220,
    ),
    RecommendationSeed(
      label: 'award winners',
      query: 'subject:"fiction" "award winning"',
      byPopularity: true,
    ),
    RecommendationSeed(
      label: 'nonfiction worth reading',
      query: 'subject:"nonfiction"',
      byPopularity: true,
    ),
  ];

  static List<RecommendationSeed> from(
    List<LibraryBook> books, {
    List<ReadingTaste> tastes = const [],
  }) {
    final seeds = <RecommendationSeed>[
      const RecommendationSeed(
        label: 'our readers read',
        source: SeedSource.readers,
      ),
    ];

    final author = _anchorAuthor(books);
    if (author != null) {
      seeds.add(
        RecommendationSeed(
          label: 'more by $author',
          query: 'inauthor:"$author"',
          byPopularity: true,
        ),
      );
    }

    for (final taste in tastes.take(maxTasteRows)) {
      seeds.add(
        RecommendationSeed(
          label: '${taste.label} for you',
          query: 'subject:"${taste.subject}"',
          byPopularity: true,
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
          byPopularity: true,
        ),
      );
    }

    return [...seeds, ...browse];
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
