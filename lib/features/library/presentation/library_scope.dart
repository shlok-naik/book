import 'package:flutter/widgets.dart';

import 'controllers/library_controller.dart';

/// Dependency-injection seam for the library feature: the app builds one
/// [LibraryController] and hands it down here, so no widget ever
/// constructs a repository or an API client of its own (and a test can
/// push a fake controller in at the root).
///
/// It is an [InheritedNotifier], so widgets that read it with
/// [LibraryScope.of] also rebuild when the controller notifies.
class LibraryScope extends InheritedNotifier<LibraryController> {
  const LibraryScope({
    super.key,
    required LibraryController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller for the enclosing scope. Throws if the widget tree
  /// has no [LibraryScope] above it — that's a wiring bug, not a runtime
  /// condition worth handling.
  static LibraryController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LibraryScope>();
    assert(scope != null, 'No LibraryScope found above this widget.');
    return scope!.notifier!;
  }

  /// Same lookup, without subscribing to rebuilds — for callbacks that
  /// only need to dispatch a command.
  static LibraryController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<LibraryScope>();
    assert(scope != null, 'No LibraryScope found above this widget.');
    return scope!.notifier!;
  }
}
