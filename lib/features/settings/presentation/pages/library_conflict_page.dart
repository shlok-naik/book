import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/analytics/app_analytics.dart';
import '../../../../core/auth/session_service.dart';
import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/diagnostics/crash_reporter.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/platform/device_name.dart';
import '../../../../core/purchases/purchases_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../goals/presentation/goal_scope.dart';
import '../../../library/presentation/library_scope.dart';
import '../../../memory/presentation/memory_scope.dart';
import '../../../paywall/presentation/widgets/soft_pill_button.dart';
import '../widgets/settings_header.dart';

/// Called once this device has switched to the email account, so every
/// controller holding the old account's data reloads. Replaceable in tests.
typedef AccountSwitched =
    Future<void> Function(BuildContext context, String userId);

Future<void> _reloadEverything(BuildContext context, String userId) async {
  final library = LibraryScope.read(context);
  final memory = MemoryScope.read(context);
  final goals = GoalScope.read(context);
  CrashReporter.identify(userId);
  AppAnalytics.identify(userId);
  reportingFailure(
    const PurchasesService().identify(userId),
    source: 'LibraryConflictPage',
    message: 'Could not move the RevenueCat identity to the linked account.',
  );
  await Future.wait([library.reset(), memory.refresh(), goals.load()]);
}

Future<void> openLibraryConflict(
  BuildContext context, {
  required SessionService session,
  required PendingAccount account,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'library_conflict'),
      builder: (_) => LibraryConflictPage(session: session, account: account),
    ),
  );
}

enum _Side { account, device }

/// The email the reader linked already has a library, and so does this
/// device: pick one. Each option shows the device it was last used on, how
/// many books it holds and when it was started. The other library is
/// deleted — after a confirmation that names what goes.
///
/// When this device's library is empty (a fresh install), there is nothing
/// to choose: it joins the email account straight away.
///
/// Leaving this page without choosing changes nothing — the device stays on
/// its own library, and linking can be tried again from settings.
class LibraryConflictPage extends StatefulWidget {
  const LibraryConflictPage({
    super.key,
    required this.session,
    required this.account,
    this.onSwitched,
    this.deviceName,
  });

  final SessionService session;
  final PendingAccount account;

  /// Test seams. Null in the app.
  final AccountSwitched? onSwitched;
  final Future<String?> Function()? deviceName;

  @override
  State<LibraryConflictPage> createState() => _LibraryConflictPageState();
}

class _LibraryConflictPageState extends State<LibraryConflictPage> {
  LibrarySummary? _accountSummary;
  LibrarySummary? _deviceSummary;
  String? _thisDevice;
  _Side? _choice;
  bool _loading = true;
  bool _busy = false;
  bool _finished = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    if (!_finished) unawaited(widget.account.dispose());
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.session.accountSummary(widget.account),
        widget.session.deviceSummary(),
      ]);
      final name = await (widget.deviceName ?? DeviceName.current)();
      if (!mounted) return;
      setState(() {
        _accountSummary = results[0];
        _deviceSummary = results[1];
        _thisDevice = name;
        _loading = false;
      });
      if (results[1].isEmpty) await _resolve(keepDevice: false);
    } on SessionException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  Future<void> _confirmChoice() async {
    final choice = _choice;
    final account = _accountSummary;
    final device = _deviceSummary;
    if (choice == null || account == null || device == null) return;
    final discarded = choice == _Side.account ? device : account;
    final where = choice == _Side.account
        ? 'this device'
        : widget.account.email;

    final confirmed = await showConfirmDialog(
      context,
      title: 'delete the other library?',
      message:
          'the library on $where — ${_books(discarded.bookCount)}'
          '${discarded.memoryCount == 0 ? '' : ' and ${discarded.memoryCount} '
                    '${discarded.memoryCount == 1 ? 'memory' : 'memories'}'}'
          " — will be deleted for good. this can't be undone.",
      confirmLabel: 'delete it',
      routeName: 'confirm_library_conflict',
    );
    if (!confirmed || !mounted) return;
    await _resolve(keepDevice: choice == _Side.device);
  }

  Future<void> _resolve({required bool keepDevice}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.keepLibrary(widget.account, keepDevice: keepDevice);
      _finished = true;
      if (!mounted) return;
      await (widget.onSwitched ?? _reloadEverything)(
        context,
        widget.account.userId,
      );
      if (!mounted) return;
      AppHaptics.accepted();
      Navigator.of(context).pop();
    } on SessionException catch (error) {
      AppLogger.error(
        'LibraryConflictPage',
        'Linking the email failed.',
        error: error,
      );
      if (!mounted) return;
      AppHaptics.rejected();
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  static String _books(int count) => '$count ${count == 1 ? 'book' : 'books'}';

  static String _date(DateTime? date) {
    if (date == null) return '—';
    final local = date.toLocal();
    return '${local.month}.${local.day}.${(local.year % 100).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final account = _accountSummary;
    final device = _deviceSummary;
    final error = _error;
    final body = context.fonts.body(
      fontSize: 14,
      height: 1.5,
      color: colors.secondaryText,
    );

    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: colors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.xl,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SettingsHeader(title: 'choose a library'),
                const SizedBox(height: AppSpacing.lg),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                    children: [
                      if (_loading || (_busy && account == null))
                        Text('checking both libraries…', style: body)
                      else if (account != null && device != null) ...[
                        Text(
                          '${widget.account.email} already has a library, and '
                          'so does this device. keep one — the other is '
                          'deleted.',
                          style: body,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _Option(
                          key: const ValueKey('keep-account'),
                          heading: 'the library on your email',
                          device: account.deviceName ?? 'another device',
                          summary: account,
                          selected: _choice == _Side.account,
                          onTap: _busy
                              ? null
                              : () => setState(() => _choice = _Side.account),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _Option(
                          key: const ValueKey('keep-device'),
                          heading: 'the library on this device',
                          device: _thisDevice ?? 'this device',
                          summary: device,
                          selected: _choice == _Side.device,
                          onTap: _busy
                              ? null
                              : () => setState(() => _choice = _Side.device),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        SoftPillButton(
                          label: _busy
                              ? 'linking…'
                              : _choice == null
                              ? 'pick one to keep'
                              : 'keep this library',
                          onPressed: _busy || _choice == null
                              ? null
                              : _confirmChoice,
                        ),
                      ],
                      if (error != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(error, style: body),
                        if (account == null)
                          TextButton(
                            onPressed: _load,
                            child: Text(
                              'try again',
                              style: context.fonts.interface(
                                fontSize: 14,
                                color: colors.accent,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    super.key,
    required this.heading,
    required this.device,
    required this.summary,
    required this.selected,
    required this.onTap,
  });

  final String heading;
  final String device;
  final LibrarySummary summary;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final started = _LibraryConflictPageState._date(summary.createdAt);
    final lastUsed = _LibraryConflictPageState._date(summary.lastSeenAt);
    final books = _LibraryConflictPageState._books(summary.bookCount);
    final label = context.fonts.interface(
      fontSize: 12,
      color: colors.secondaryText,
    );
    final value = context.fonts.interface(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: colors.primaryText,
    );

    return Semantics(
      button: true,
      selected: selected,
      label:
          '$heading. $device. $books. started $started. last used $lastUsed.',
      excludeSemantics: true,
      onTap: onTap == null
          ? null
          : () {
              if (!selected) AppHaptics.selection();
              onTap!();
            },
      child: Material(
        color: selected
            ? colors.accent.withValues(alpha: 0.08)
            : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(
            color: selected ? colors.accent : colors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap == null
              ? null
              : () {
                  if (!selected) AppHaptics.selection();
                  onTap!();
                },
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        heading,
                        style: context.fonts.interface(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colors.primaryText,
                        ),
                      ),
                    ),
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: selected ? colors.accent : colors.secondaryText,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(device, style: label.copyWith(fontSize: 13)),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(child: _Fact('books', books, label, value)),
                    Expanded(child: _Fact('started', started, label, value)),
                    Expanded(child: _Fact('last used', lastUsed, label, value)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value, this.labelStyle, this.valueStyle);

  final String label;
  final String value;
  final TextStyle labelStyle;
  final TextStyle valueStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle),
        Text(value, style: valueStyle),
      ],
    );
  }
}
