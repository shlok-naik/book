import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show CustomerInfo;

import '../../../../core/purchases/plan_controller.dart';
import '../../../../core/purchases/purchases_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/theme_controller.dart';

/// The app's one account/settings surface — currently just the
/// subscription section: whether "cactus pro" is active, RevenueCat's
/// own Customer Center for self-serve manage/cancel/refund-request
/// flows, and a restore-purchases fallback for a reinstall or a new
/// device. Everything else here is still a placeholder.
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

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'profile',
                style: GoogleFonts.ebGaramond(
                  fontSize: 28,
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
