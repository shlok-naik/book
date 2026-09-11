import 'package:flutter/widgets.dart';

import 'controllers/memory_controller.dart';

/// Dependency-injection seam for the memory feature — mirrors
/// `LibraryScope` exactly, down to the reasoning: the app builds one
/// [MemoryController] and hands it down here, so no widget constructs a
/// repository of its own (and a test can push a fake controller in at
/// the root).
class MemoryScope extends InheritedNotifier<MemoryController> {
  const MemoryScope({
    super.key,
    required MemoryController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller for the enclosing scope. Throws if the widget tree
  /// has no [MemoryScope] above it — that's a wiring bug, not a runtime
  /// condition worth handling.
  static MemoryController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MemoryScope>();
    assert(scope != null, 'No MemoryScope found above this widget.');
    return scope!.notifier!;
  }

  /// Same lookup, without subscribing to rebuilds — for callbacks that
  /// only need to dispatch a command.
  static MemoryController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<MemoryScope>();
    assert(scope != null, 'No MemoryScope found above this widget.');
    return scope!.notifier!;
  }
}
