import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show CustomerInfo;

import '../../../../core/purchases/plan_controller.dart';
import '../../../../core/purchases/purchases_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../memory/domain/memory.dart';
import '../../../memory/presentation/controllers/memory_controller.dart';
import '../../../memory/presentation/memory_scope.dart';

/// The app's one account/settings surface: whether "cactus pro" is
/// active, RevenueCat's own Customer Center for self-serve
/// manage/cancel/refund-request flows, a restore-purchases fallback for
/// a reinstall or a new device, and the reader's own memory list — the
/// notes "cactus pro"'s `remember` command has saved, and what
/// `recommend` grounds its picks in. Everything else here is still a
/// placeholder.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.purchases});

  /// Injection point for tests: a fake wrapping fake customer info
  /// instead of the real RevenueCat SDK. Null in the app.
  final PurchasesService? purchases;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final PurchasesService _purchases =
      widget.purchases ?? const PurchasesService();

  CustomerInfo? _info;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
    // `read`, not `of`: a one-off kick of the fetch, not a rebuild
    // dependency — `build` below reads the controller through
    // `MemoryScope.of` instead, so this page still rebuilds once the
    // fetch resolves.
    //
    // Deferred to the post-frame callback: `MemoryScope` wraps the
    // whole app, so a `notifyListeners()` fired synchronously from here
    // — still inside the very first build — would try to rebuild an
    // ancestor that is itself mid-mount (see `HomePage.initState`'s own
    // copy of this reasoning).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(MemoryScope.read(context).load());
    });
  }

  Future<void> _refresh() async {
    try {
      final info = await _purchases.customerInfo;
      if (!mounted) return;
      setState(() => _info = info);
    } on PurchasesException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    }
  }

  Future<void> _manageSubscription() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _purchases.presentCustomerCenter();
      // Customer Center can itself change entitlements (a cancel, a
      // plan switch) — refresh once the reader closes it rather than
      // trusting whatever was true before they opened it.
      await _refresh();
    } on PurchasesException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restorePurchases() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final info = await _purchases.restore();
      if (!mounted) return;
      setState(() => _info = info);
    } on PurchasesException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final info = _info;
    final isPro = info != null && _purchases.isPro(info);
    // `of`, not `read`: the memory list itself is rendered below, so
    // this page needs to rebuild whenever `remember`/`forget` changes
    // it — unlike the one-off `load()` kick in `initState`.
    final memory = MemoryScope.of(context);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'profile',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _SubscriptionCard(
                loading: info == null && _error == null,
                isPro: isPro,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: colors.secondaryText,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              _AccountAction(
                icon: Icons.manage_accounts_outlined,
                label: 'manage subscription',
                onTap: _busy ? null : _manageSubscription,
              ),
              const SizedBox(height: AppSpacing.sm),
              _AccountAction(
                icon: Icons.restore,
                label: 'restore purchases',
                onTap: _busy ? null : _restorePurchases,
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _DarkModeSwitch(),
                  const SizedBox(width: AppSpacing.md),
                  const _PlanSwitch(),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'memory',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.secondaryText,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // The one variable-height section on this page — flexed
              // so a long memory list scrolls in place instead of
              // pushing the fixed sections above off screen.
              Expanded(child: _MemorySection(controller: memory)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Loading / free / pro — the three states worth showing at a glance,
/// before the reader ever has to open Customer Center to find out.
class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({required this.loading, required this.isPro});

  final bool loading;
  final bool isPro;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final String title;
    final String subtitle;
    if (loading) {
      title = 'checking subscription…';
      subtitle = '';
    } else if (isPro) {
      title = 'cactus pro';
      subtitle = 'your subscription is active.';
    } else {
      title = 'free plan';
      subtitle = 'upgrade any time from the paywall.';
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (isPro ? colors.accent : colors.secondaryText).withValues(
                alpha: 0.15,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPro ? Icons.auto_awesome : Icons.person_outline,
              color: isPro ? colors.accent : colors.secondaryText,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: colors.secondaryText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One tappable row — an icon, a label, and a chevron. Plain
/// [ListTile]-shaped rather than a pill: this is a settings list, not
/// a call to action competing for attention.
class _AccountAction extends StatelessWidget {
  const _AccountAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: colors.secondaryText),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: colors.secondaryText),
            ],
          ),
        ),
      ),
    );
  }
}

/// Debug-only toggle for forcing light/dark mode, independent of the
/// system setting — lets us eyeball both themes without leaving the app.
class _DarkModeSwitch extends StatelessWidget {
  const _DarkModeSwitch();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, mode, _) {
        final isDark = mode == ThemeMode.dark;
        return GestureDetector(
          onTap: ThemeController.toggle,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isDark ? Icons.dark_mode : Icons.light_mode,
                size: 14,
                color: colors.secondaryText,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                isDark ? 'dark' : 'light',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: colors.secondaryText,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Debug-only toggle for forcing the "cactus pro" plan state,
/// independent of any real RevenueCat entitlement — lets us eyeball
/// both the free and pro experience without a real purchase.
class _PlanSwitch extends StatelessWidget {
  const _PlanSwitch();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ValueListenableBuilder<bool>(
      valueListenable: PlanController.isPro,
      builder: (context, isPro, _) {
        return GestureDetector(
          onTap: PlanController.toggle,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isPro ? Icons.auto_awesome : Icons.person_outline,
                size: 14,
                color: colors.secondaryText,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                isPro ? 'pro' : 'free',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: colors.secondaryText,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The reader's saved memories — loading / error / empty / list, in
/// that order of what to show. Rebuilds automatically whenever
/// [controller] changes (see [MemoryScope.of] in [ProfilePage.build]).
class _MemorySection extends StatelessWidget {
  const _MemorySection({required this.controller});

  final MemoryController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (controller.isLoading && controller.memories.isEmpty) {
      return Text(
        'loading memories…',
        style: GoogleFonts.inter(fontSize: 13, color: colors.secondaryText),
      );
    }

    final error = controller.errorMessage;
    if (error != null && controller.memories.isEmpty) {
      return Text(
        error,
        style: GoogleFonts.inter(fontSize: 13, color: colors.secondaryText),
      );
    }

    if (controller.memories.isEmpty) {
      return Text(
        'Nothing remembered yet. On cactus pro, say something like '
        '"I loved the ending of Dune" and it\'ll show up here — and '
        'shape what "recommend" suggests next.',
        style: GoogleFonts.inter(
          fontSize: 13,
          height: 1.4,
          color: colors.secondaryText,
        ),
      );
    }

    return ListView.separated(
      itemCount: controller.memories.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final memory = controller.memories[index];
        return _MemoryRow(
          memory: memory,
          onDelete: () => controller.forget(memory.id),
        );
      },
    );
  }
}

/// One remembered note — the book it's about (if any), then the note
/// itself, with a delete affordance. Plain row, matching
/// [_AccountAction]'s surface rather than a card of its own, since this
/// is a list rather than a single call to action.
class _MemoryRow extends StatelessWidget {
  const _MemoryRow({required this.memory, required this.onDelete});

  final Memory memory;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = memory.bookTitle;

    return Semantics(
      label: title == null ? memory.note : '$title. ${memory.note}',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.primaryText,
                      ),
                    ),
                  Text(
                    memory.note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: colors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            Semantics(
              button: true,
              label: 'Forget this memory',
              child: IconButton(
                onPressed: onDelete,
                icon: Icon(Icons.close, size: 18, color: colors.secondaryText),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
