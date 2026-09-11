import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/profile_exception.dart';

/// Reads and writes the one thing the settings screen's membership card
/// needs from `profiles` beyond what [SessionService] already exposes: a
/// profile picture. Stateless, like `PurchasesService` — safe to
/// construct wherever it's needed rather than threading a single
/// instance through the tree.
class ProfileRepository {
  const ProfileRepository({SupabaseClient? client}) : _injectedClient = client;

  final SupabaseClient? _injectedClient;

  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  static const _bucket = 'avatars';
  static const _timeout = Duration(seconds: 20);

  /// The reader's current profile picture, or null if they've never set
  /// one.
  Future<String?> fetchAvatarUrl(String userId) {
    return _run(() async {
      final row = await _client
          .from('profiles')
          .select('avatar_url')
          .eq('id', userId)
          .maybeSingle();
      final url = row?['avatar_url'];
      return url is String && url.isNotEmpty ? url : null;
    }, friendlyMessage: "We couldn't load your profile picture.");
  }

  /// Uploads [bytes] as the reader's new profile picture — to
  /// `<userId>/avatar.<extension>` in the public `avatars` bucket, one
  /// object per reader, overwritten on every change — then saves the
  /// result to `profiles.avatar_url` and returns the URL the card should
  /// show.
  ///
  /// [extension] (no leading dot) is whatever the picked file's own
  /// extension was, so the object's inferred content type matches its
  /// actual bytes.
  Future<String> uploadAvatar({
    required String userId,
    required Uint8List bytes,
    required String extension,
  }) {
    return _run(() async {
      final path = '$userId/avatar.$extension';
      await _client.storage
          .from(_bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );

      // Cache-busted: the object lives at the same path every time a
      // reader changes their picture, and an unqualified URL would keep
      // showing whatever `Image.network` (or a CDN in front of it)
      // cached the first time it was fetched.
      final publicUrl = _client.storage.from(_bucket).getPublicUrl(path);
      final url = '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';

      await _client
          .from('profiles')
          .update({'avatar_url': url})
          .eq('id', userId);
      return url;
    }, friendlyMessage: "We couldn't update your profile picture.");
  }

  Future<T> _run<T>(
    Future<T> Function() action, {
    required String friendlyMessage,
  }) async {
    try {
      return await action().timeout(_timeout);
    } on TimeoutException catch (error) {
      throw ProfileException(
        'That took too long. Check your connection and try again.',
        cause: error,
      );
    } on SocketException catch (error) {
      throw ProfileException(
        "You're offline — connect to the internet and try again.",
        cause: error,
      );
    } on http.ClientException catch (error) {
      throw ProfileException(
        "We couldn't reach the server. Try again in a moment.",
        cause: error,
      );
    } on Object catch (error) {
      // Covers StorageException, PostgrestException, and an
      // uninitialized `Supabase.instance` (an AssertionError, not an
      // Exception) alike — all of them need to degrade to a visible
      // message rather than a crash.
      throw ProfileException(friendlyMessage, cause: error);
    }
  }
}
