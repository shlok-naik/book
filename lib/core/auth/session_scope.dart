import 'package:flutter/widgets.dart';

import 'session_service.dart';

/// Dependency-injection seam for the session — mirrors `LibraryScope`
/// and `MemoryScope`, for the same reason: the app builds one
/// [SessionService] at its composition root and hands it down here, so
/// no widget reaches for `Supabase.instance` itself (and a test can push
/// a fake in at the root).
///
/// An [InheritedWidget] rather than an [InheritedNotifier]: a session
/// does not change under the app while it runs. Linking an email in
/// settings mutates the *same* user rather than replacing it, so there
/// is nothing here for a listener to be told about.
class SessionScope extends InheritedWidget {
  const SessionScope({super.key, required this.session, required super.child});

  final SessionService session;

  static SessionService of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SessionScope>();
    assert(scope != null, 'No SessionScope found above this widget.');
    return scope!.session;
  }

  @override
  bool updateShouldNotify(SessionScope oldWidget) =>
      session != oldWidget.session;
}
