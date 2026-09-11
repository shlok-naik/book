import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show CustomerInfo;

import '../../../../core/auth/session_scope.dart';
import '../../../../core/auth/session_service.dart';
import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/purchases/plan_controller.dart';
import '../../../../core/purchases/purchases_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../paywall/presentation/pages/paywall_page.dart';
import '../../data/avatar_picker.dart';
import '../../data/profile_repository.dart';
import '../widgets/membership_card.dart';
import '../widgets/settings_section.dart';

/// Everything that isn't reading: the account the shelf actually belongs
/// to, the subscription, how the app looks, and the legal small print.
///
/// One screen behind one gear rather than a fifth tab — none of this is
/// something a reader does daily, and giving it a tab would cost one of
/// the four that are. It is pushed from `TopBar`, which puts the same
/// gear in the same top-right corner on all four top-level pages.
///
/// The account itself is `MembershipCard`, at the very top — a profile
/// picture and the email `linkEmail` attaches, styled like a membership
/// card rather than a settings row. There is no separate "account"
/// section any more: this card is the only place that email is shown or
/// changed, and the only place a profile picture lives.
///
/// Dressed like the rest of the app rather than like Material: no
/// [AppBar] (nothing else in this app has one, and its default tint,
/// elevation and centred title belong to a different design language),
/// but the same `Scaffold` + `SafeArea` + `AppSpacing.xl` gutter, the
/// same lowercase `jetBrainsMono` heading, and rows built from
/// `AppColors`/`AppRadius` tokens — never a hardcoded hex.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    this.purchases,
    this.session,
    this.profileRepository,
    this.avatarPicker,
  });

  /// Injection point for tests: a fake wrapping fake customer info
  /// instead of the real RevenueCat SDK. Null in the app.
  final PurchasesService? purchases;

  /// Injection point for tests. Null in the app, where the session comes
  /// from the [SessionScope] the composition root installs.
  final SessionService? session;

  /// Injection point for tests: a fake wrapping fake storage/profile
  /// calls instead of the real Supabase SDK. Null in the app. Threaded
  /// straight through to [MembershipCard].
  final ProfileRepository? profileRepository;

  /// Injection point for tests: a fake that hands back canned bytes
  /// instead of opening the real photo library. Null in the app.
  /// Threaded straight through to [MembershipCard].
  final AvatarPicker? avatarPicker;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final PurchasesService _purchases =
      widget.purchases ?? const PurchasesService();

  CustomerInfo? _info;
  bool _busy = false;
  String? _error;

  /// The app version, shown in the about section so a support
  /// conversation can start from a fact rather than a guess.
  ///
  /// Hardcoded from `pubspec.yaml` deliberately: reading it at runtime
  /// means another plugin, and the one that does it needs Windows
  /// Developer Mode to install here. **Keep this in step with
  /// `version:` in pubspec.yaml.**
  static const _version = '1.0.0';

  SessionService get _session => widget.session ?? SessionScope.of(context);

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
    } on Object catch (error, stackTrace) {
      // Anything the store SDK throws that isn't already a translated
      // [PurchasesException] — an SDK that was never configured, most
      // likely. The rest of this page (appearance, account, about) works
      // perfectly well without it, so it degrades to a line of text
      // instead of taking the whole screen down.
      AppLogger.error(
        'SettingsPage',
        'Could not read the subscription state.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() => _error = "We couldn't check your subscription right now.");
    }
  }

  Future<void> _manageSubscription() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _purchases.presentCustomerCenter();
      // Customer Center can itself change entitlements (a cancel, a plan
      // switch) — refresh once the reader closes it rather than trusting
      // whatever was true before they opened it.
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

  Future<void> _upgrade() async {
    await showPaywallPopup(context, purchases: widget.purchases);
    // A purchase made in there is invisible to this page otherwise — the
    // card above would still say "free plan" until the next launch.
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final info = _info;
    final isPro = info != null && _purchases.isPro(info);
    final session = _session;
    final error = _error;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Padding(
          // Same gutter and same top inset as the streaks, library and
          // memory pages, so pushing this screen doesn't shift the
          // heading a single pixel from where the reader last saw one.
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SettingsHeader(),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                  children: [
                    MembershipCard(
                      session: session,
                      isPro: isPro,
                      profileRepository: widget.profileRepository,
                      avatarPicker: widget.avatarPicker,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _SubscriptionCard(
                      loading: info == null && error == null,
                      isPro: isPro,
                    ),
                    if (error != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        error,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    SettingsSection(
                      title: 'cactus pro',
                      rows: [
                        if (!isPro)
                          SettingsRow(
                            icon: Icons.auto_awesome,
                            label: 'get cactus pro',
                            onTap: _busy ? null : _upgrade,
                          ),
                        SettingsRow(
                          icon: Icons.manage_accounts_outlined,
                          label: 'manage subscription',
                          onTap: _busy ? null : _manageSubscription,
                        ),
                        SettingsRow(
                          icon: Icons.restore,
                          label: 'restore purchases',
                          onTap: _busy ? null : _restorePurchases,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const _AppearanceSection(),
                    const SizedBox(height: AppSpacing.lg),
                    SettingsSection(
                      title: 'about',
                      rows: [
                        SettingsRow(
                          icon: Icons.info_outline,
                          label: 'version',
                          value: _version,
                        ),
                        SettingsRow(
                          icon: Icons.description_outlined,
                          label: 'open source licenses',
                          onTap: () => showLicensePage(
                            context: context,
                            applicationName: 'cactus',
                            applicationVersion: _version,
                          ),
                        ),
                      ],
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: AppSpacing.lg),
                      const _DebugSection(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The screen's own heading: a back chevron, then the name, in the same
/// lowercase `jetBrainsMono` every other page's heading uses.
///
/// Deliberately not an [AppBar]. Nothing else in this app has one, and
/// its Material defaults — the surface tint, the elevation shadow on
/// scroll, the centred title — would make the one screen a reader opens
/// least look like it came from a different app than the four they use
/// daily. The geometry matches [TopBar] exactly, so the heading lands on
/// the same baseline as the one they just tapped away from.
class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader();

  /// The same 44pt square [TopBar] gives its gear.
  static const _tapTarget = 44.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      height: _tapTarget,
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Back',
            excludeSemantics: true,
            child: InkResponse(
              onTap: Navigator.of(context).pop,
              radius: _tapTarget / 2,
              child: SizedBox(
                width: _tapTarget,
                height: _tapTarget,
                // Left-aligned inside the target, mirroring what the
                // gear does on the right on every other page.
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Icon(
                    Icons.chevron_left,
                    size: 24,
                    color: colors.secondaryText,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'settings',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: colors.primaryText,
              ),
            ),
          ),
        ],
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
      subtitle = 'remember and recommend are pro commands.';
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

/// Light / dark / system, as three mutually exclusive choices rather
/// than a switch — "system" is a real answer, and a two-state toggle has
/// nowhere to put it.
class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

  static const _options = <ThemeMode, (String, IconData)>{
    ThemeMode.light: ('light', Icons.light_mode_outlined),
    ThemeMode.dark: ('dark', Icons.dark_mode_outlined),
    ThemeMode.system: ('system', Icons.brightness_auto_outlined),
  };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, mode, _) {
        return SettingsSection(
          title: 'appearance',
          rows: [
            for (final entry in _options.entries)
              SettingsRow(
                icon: entry.value.$2,
                label: entry.value.$1,
                trailing: _Check(selected: mode == entry.key),
                onTap: () {
                  // Picking the mode you are already in is not a move,
                  // so it gets no haptic — same rule as the tab bar.
                  if (mode == entry.key) return;
                  AppHaptics.selection();
                  ThemeController.select(entry.key);
                },
              ),
          ],
        );
      },
    );
  }
}

/// The selected marker for a row that is one of several choices. Sized
/// whether or not it is showing, so picking a different option doesn't
/// shift the rows around it.
class _Check extends StatelessWidget {
  const _Check({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: selected
          ? Icon(Icons.check, size: 20, color: context.colors.accent)
          : null,
    );
  }
}

/// Debug-only override for a state that otherwise needs a real purchase
/// to reach. Never compiled into a release build.
class _DebugSection extends StatelessWidget {
  const _DebugSection();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PlanController.isPro,
      builder: (context, isPro, _) {
        return SettingsSection(
          title: 'debug',
          rows: [
            SettingsRow(
              icon: isPro ? Icons.auto_awesome : Icons.person_outline,
              label: 'pretend plan',
              value: isPro ? 'pro' : 'free',
              onTap: PlanController.toggle,
            ),
          ],
        );
      },
    );
  }
}
