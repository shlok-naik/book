import 'package:flutter/foundation.dart';

import '../../data/memory_repository.dart';
import '../../domain/memory.dart';
import '../../domain/memory_exception.dart';

/// Outcome of a memory command, in a form the log page can show —
/// mirrors `LibraryActionResult`'s shape exactly, kept as its own type
/// rather than imported from the library feature so this feature stays
/// self-contained (see `MemoryException`'s own doc comment for the same
/// reasoning).
class MemoryActionResult {
  const MemoryActionResult.success([this.message]) : success = true;
  const MemoryActionResult.failure(this.message) : success = false;

  final bool success;
  final String? message;
}

/// Holds the reader's saved memories and applies `remember`/`forget` to
/// them — the profile page's memory list and the log page's `remember`
/// command both go through this rather than talking to Supabase
/// directly, same relationship `LibraryController` has with the shelf.
///
/// [remember] and [forget] are optimistic: local state updates and
/// notifies immediately, then persists, rolling back on failure — same
/// convention as every `LibraryController` command (see CLAUDE.md
/// § Supabase model).
class MemoryController extends ChangeNotifier {
  MemoryController({MemoryRepository? repository})
    : repository = repository ?? MemoryRepository();

  final MemoryRepository repository;

  List<Memory> _memories = const [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _hasLoaded = false;

  List<Memory> get memories => _memories;
  bool get isLoading => _isLoading;

  /// Set when the last *load* failed, so the profile page can show a
  /// retry rather than an empty list. Command failures are reported
  /// through [MemoryActionResult] instead.
  String? get errorMessage => _errorMessage;

  /// Fetches every saved memory. A second call is a no-op once the
  /// first has already succeeded — same "load once" convention
  /// `StreaksController` uses per year — so reopening the profile page
  /// doesn't re-fetch on every visit; call [refresh] to force one.
  Future<void> load() {
    if (_hasLoaded) return Future.value();
    return refresh();
  }

  Future<void> refresh() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _memories = await repository.fetchAll();
      _hasLoaded = true;
    } on MemoryException catch (error) {
      _errorMessage = error.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Saves a new memory, optimistically inserting a placeholder entry
  /// first so the log page's confirmation pill and the profile page's
  /// list both reflect it immediately, then swapping in the real
  /// persisted row (or rolling the placeholder back on failure).
  Future<MemoryActionResult> remember({
    String? bookTitle,
    required String note,
  }) async {
    final placeholder = Memory(
      id: '_pending_${DateTime.now().microsecondsSinceEpoch}',
      bookTitle: bookTitle,
      note: note,
      createdAt: DateTime.now(),
    );
    _memories = [placeholder, ..._memories];
    notifyListeners();

    try {
      final saved = await repository.add(bookTitle: bookTitle, note: note);
      final index = _memories.indexWhere((m) => m.id == placeholder.id);
      if (index != -1) {
        final next = [..._memories];
        next[index] = saved;
        _memories = next;
        notifyListeners();
      }
      return const MemoryActionResult.success();
    } on MemoryException catch (error) {
      _memories = _memories.where((m) => m.id != placeholder.id).toList();
      notifyListeners();
      return MemoryActionResult.failure(error.message);
    }
  }

  Future<MemoryActionResult> forget(String id) async {
    final removed = _memories.where((m) => m.id == id).toList();
    _memories = _memories.where((m) => m.id != id).toList();
    notifyListeners();

    try {
      await repository.delete(id);
      return const MemoryActionResult.success();
    } on MemoryException catch (error) {
      if (removed.isNotEmpty) {
        _memories = [...removed, ..._memories];
        notifyListeners();
      }
      return MemoryActionResult.failure(error.message);
    }
  }
}
