import 'package:flutter/material.dart';

import '../feedback/app_haptics.dart';
import '../network/connectivity_controller.dart';
import '../offline/sync_scope.dart';
import '../theme/app_colors.dart';
import '../theme/app_fonts.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// The "no internet" mark every page header carries just left of its
/// right-hand icon — `TopBar`'s settings gear on the four tabs, and
/// `SettingsHeader`'s back chevron on settings and every page pushed from
/// it — so wherever a reader is, they can tell their changes are being
/// kept on the device rather than wondering whether a command "took".
///
/// Three states, and it takes no room at all in the common one:
///
/// * **online, nothing waiting** — nothing is drawn.
/// * **offline** — a crossed-out cloud. Tapping it explains, in one short
///   sheet, that changes are saved on this device and how many are waiting.
/// * **back online, still sending** — a syncing cloud, until the queue
///   drains.
///
/// Reads [ConnectivityController] directly and the queue through the
/// optional [SyncScope], so a header pumped in a test with neither shows
/// nothing, exactly as before this existed.
class OfflineIndicator extends StatelessWidget {
  const OfflineIndicator({super.key});

  /// Matches the header row's own 44pt tap target.
  static const _tapTarget = 44.0;

  @override
  Widget build(BuildContext context) {
    final sync = SyncScope.maybeOf(context);
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityController.isOffline,
      builder: (context, offline, _) {
        if (sync == null) {
          return offline ? _Mark.offline(pending: 0) : const SizedBox.shrink();
        }
        return ValueListenableBuilder<int>(
          valueListenable: sync.queue.pendingCount,
          builder: (context, pending, _) => ValueListenableBuilder<bool>(
            valueListenable: sync.coordinator.isSyncing,
            builder: (context, syncing, _) {
              if (offline) return _Mark.offline(pending: pending);
              if (syncing || pending > 0) return _Mark.syncing(pending);
              return const SizedBox.shrink();
            },
          ),
        );
      },
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark._({
    required this.icon,
    required this.label,
    required this.pending,
    required this.offline,
  });

  factory _Mark.offline({required int pending}) => _Mark._(
    icon: Icons.cloud_off_outlined,
    offline: true,
    pending: pending,
    label: pending == 0
        ? 'Offline. Changes you make are saved on this device.'
        : 'Offline. ${_changes(pending)} saved on this device will sync '
              'when you reconnect.',
  );

  factory _Mark.syncing(int pending) => _Mark._(
    icon: Icons.cloud_sync_outlined,
    offline: false,
    pending: pending,
    label: 'Back online. Syncing ${_changes(pending)}.',
  );

  final IconData icon;
  final String label;
  final int pending;
  final bool offline;

  static String _changes(int count) =>
      count == 1 ? '1 change' : '$count changes';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: offline,
      liveRegion: true,
      label: label,
      excludeSemantics: true,
      onTap: offline ? () => _explain(context) : null,
      child: Tooltip(
        message: offline ? 'offline' : 'syncing',
        child: SizedBox(
          key: ValueKey(offline ? 'offline-indicator' : 'syncing-indicator'),
          width: OfflineIndicator._tapTarget,
          height: OfflineIndicator._tapTarget,
          child: InkResponse(
            radius: OfflineIndicator._tapTarget / 2,
            onTap: offline ? () => _explain(context) : null,
            child: Icon(icon, size: 20, color: colors.secondaryText),
          ),
        ),
      ),
    );
  }

  void _explain(BuildContext context) {
    AppHaptics.selection();
    final colors = context.colors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      useSafeArea: true,
      routeSettings: const RouteSettings(name: 'offline_info'),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "you're offline",
              style: context.fonts.interface(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'progress, finishes, ratings and shelf moves still save — '
              'they stay on this device and sync as soon as you reconnect. '
              'adding a new book needs a connection, and so does natural '
              'language — typed commands work either way.',
              style: context.fonts.body(
                fontSize: 14,
                height: 1.5,
                color: colors.secondaryText,
              ),
            ),
            if (pending > 0) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                '${_changes(pending)} waiting to sync',
                style: context.fonts.interface(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.accent,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
