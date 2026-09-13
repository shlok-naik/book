import 'package:supabase_flutter/supabase_flutter.dart';

/// The email the reader tried to link already belongs to another library.
/// The way forward is to sign in to that account and choose a library —
/// see `LibraryConflictPage`.
class EmailInUseException implements Exception {
  const EmailInUseException(this.email);

  final String email;
}

/// An email account this device has signed in to on a *separate* client,
/// while the device's own anonymous session stays current — so both
/// libraries can be summarised side by side before either is touched.
class PendingAccount {
  PendingAccount({
    required this.userId,
    required this.email,
    required this.refreshToken,
    this.client,
  });

  final String userId;
  final String email;

  /// What this device switches its own session to once a library is chosen.
  final String? refreshToken;

  /// The separate client signed in to this account; null in tests.
  final SupabaseClient? client;

  Future<void> dispose() async => client?.dispose();
}

/// What one side of the library choice shows: `library_summary()`.
class LibrarySummary {
  const LibrarySummary({
    required this.bookCount,
    required this.memoryCount,
    required this.eventCount,
    this.createdAt,
    this.deviceName,
    this.lastSeenAt,
  });

  final int bookCount;
  final int memoryCount;
  final int eventCount;

  /// When the account was created — "started".
  final DateTime? createdAt;

  /// The device that last opened it, as it named itself.
  final String? deviceName;
  final DateTime? lastSeenAt;

  /// Nothing worth choosing: a fresh install can just join the account.
  bool get isEmpty => bookCount == 0 && memoryCount == 0 && eventCount == 0;

  static LibrarySummary fromRow(Map<String, dynamic> row) {
    int count(String key) => switch (row[key]) {
      final num value => value.toInt(),
      final String value => int.tryParse(value) ?? 0,
      _ => 0,
    };
    DateTime? date(String key) =>
        row[key] is String ? DateTime.tryParse(row[key] as String) : null;
    final name = row['device_name'];
    return LibrarySummary(
      bookCount: count('book_count'),
      memoryCount: count('memory_count'),
      eventCount: count('event_count'),
      createdAt: date('created_at'),
      deviceName: name is String && name.trim().isNotEmpty ? name.trim() : null,
      lastSeenAt: date('last_seen_at'),
    );
  }
}
