import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../diagnostics/app_logger.dart';

/// Where the offline layer keeps its JSON documents — the cached shelf,
/// the cached journal year, the pending-write queue. An interface so tests
/// use [MemoryOfflineStore] and never touch the file system.
///
/// Documents are namespaced by account (see [FileOfflineStore]): a device
/// that links an email and swaps libraries must never replay one
/// account's queued writes, or show its cached shelf, under another uid.
abstract interface class OfflineStore {
  /// The document at [key], or null when there is none (or it can't be
  /// read — a corrupt file is treated as absent, never as a crash).
  Future<Object?> read(String key);

  /// Replaces the document at [key]. Failures are logged, never thrown: a
  /// cache that couldn't be written costs offline fidelity, not the write
  /// the reader just made.
  Future<void> write(String key, Object? value);

  Future<void> delete(String key);
}

/// [OfflineStore] on disk: one JSON file per key under
/// `<application support>/offline/<account>/`. Application support rather
/// than documents or cache — the OS may purge a cache directory, and a
/// purged queue is a lost write.
class FileOfflineStore implements OfflineStore {
  FileOfflineStore({
    required this.accountId,
    Future<Directory> Function()? root,
  }) : _root = root ?? getApplicationSupportDirectory;

  /// The uid whose documents these are. Only ever a path segment built
  /// from a Supabase uuid, never reader-authored text.
  final String accountId;

  final Future<Directory> Function() _root;
  Directory? _dir;

  Future<Directory> _directory() async {
    final existing = _dir;
    if (existing != null) return existing;
    final base = await _root();
    final safe = accountId.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '_');
    final dir = Directory('${base.path}/offline/$safe');
    await dir.create(recursive: true);
    return _dir = dir;
  }

  Future<File> _file(String key) async {
    final safe = key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${(await _directory()).path}/$safe.json');
  }

  @override
  Future<Object?> read(String key) async {
    try {
      final file = await _file(key);
      if (!file.existsSync()) return null;
      return jsonDecode(await file.readAsString());
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'FileOfflineStore',
        'Could not read the offline "$key" document; treating it as empty.',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// The last write queued for each key. Writes to one key run one after
  /// another: two overlapping writes used to share a single `.tmp` sibling,
  /// so their bytes could interleave into a file that no longer parses —
  /// and an unreadable pending-write queue is read back as *empty*, which
  /// silently loses every change waiting to sync.
  final _writes = <String, Future<void>>{};
  var _tempCounter = 0;

  @override
  Future<void> write(String key, Object? value) {
    // Encoded now, not when this write's turn comes: the caller may keep
    // mutating the structure it passed.
    final String encoded;
    try {
      encoded = jsonEncode(value);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'FileOfflineStore',
        'Could not encode the offline "$key" document.',
        error: error,
        stackTrace: stackTrace,
      );
      return Future.value();
    }
    return _inTurn(key, () => _writeNow(key, encoded));
  }

  /// Runs [operation] once every earlier write or delete of [key] is done.
  Future<void> _inTurn(String key, Future<void> Function() operation) {
    final previous = _writes[key] ?? Future.value();
    final next = previous.then((_) => operation());
    _writes[key] = next;
    return next.whenComplete(() {
      if (identical(_writes[key], next)) _writes.remove(key);
    });
  }

  Future<void> _writeNow(String key, String encoded) async {
    try {
      final file = await _file(key);
      // Written to a sibling and renamed over the original, so a crash
      // mid-write leaves the previous document rather than half a file.
      final temp = File('${file.path}.${_tempCounter++}.tmp');
      await temp.writeAsString(encoded, flush: true);
      await temp.rename(file.path);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'FileOfflineStore',
        'Could not write the offline "$key" document.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> delete(String key) => _inTurn(key, () => _deleteNow(key));

  Future<void> _deleteNow(String key) async {
    try {
      final file = await _file(key);
      if (file.existsSync()) await file.delete();
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'FileOfflineStore',
        'Could not delete the offline "$key" document.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}

/// [OfflineStore] in memory — tests, and nothing else. Round-trips values
/// through JSON so a test catches anything the file store couldn't save.
class MemoryOfflineStore implements OfflineStore {
  final _documents = <String, String>{};

  @override
  Future<Object?> read(String key) async {
    final raw = _documents[key];
    return raw == null ? null : jsonDecode(raw);
  }

  @override
  Future<void> write(String key, Object? value) async {
    _documents[key] = jsonEncode(value);
  }

  @override
  Future<void> delete(String key) async {
    _documents.remove(key);
  }
}
