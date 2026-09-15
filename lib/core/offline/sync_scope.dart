import 'package:flutter/widgets.dart';

import 'pending_write_queue.dart';
import 'sync_coordinator.dart';

/// Hands the offline layer's live state down to the one widget that shows
/// it — `OfflineIndicator` — without every page header having to be given
/// a coordinator. Installed by the composition root when offline support
/// is on.
///
/// Optional on purpose ([maybeOf]): most widget tests pump a page with no
/// offline layer at all, and the indicator then simply reads connectivity
/// alone.
class SyncScope extends InheritedWidget {
  const SyncScope({
    super.key,
    required this.queue,
    required this.coordinator,
    required super.child,
  });

  final PendingWriteQueue queue;
  final SyncCoordinator coordinator;

  static SyncScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SyncScope>();

  @override
  bool updateShouldNotify(SyncScope oldWidget) =>
      queue != oldWidget.queue || coordinator != oldWidget.coordinator;
}
