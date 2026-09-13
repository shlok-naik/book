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
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../paywall/presentation/pages/paywall_page.dart';
import '../../data/profile_repository.dart';
import '../widgets/membership_card.dart';
import '../widgets/settings_header.dart';
import '../widgets/settings_section.dart';
import 'customisation_page.dart';

/// Everything that isn't reading: the account the shelf actually belongs
/// to, the subscription, how the app looks, and the legal small print.
///
/// One screen behind one gear rather than a fifth tab — none of this is
/// something a reader does daily, and giving it a tab would cost one of
/// the four that are. It is pushed from `TopBar`, which puts the same
/// gear in the same top-right corner on all four top-level pages.
///
/// The account itself is `MembershipCard`, at the very top — the join
/// date and the email `linkEmail` attaches, styled like a flat
/// membership card rather than a settings row. There is no separate
/// "account" section any more: this card is the only place that email
/// is shown or changed.
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
  });

  /// Injection point for tests: a fake wrapping fake customer info
  /// instead of the real RevenueCat SDK. Null in the app.
  final PurchasesService? purchases;

  /// Injection point for tests. Null in the app, where the session comes
  /// from the [SessionScope] the composition root installs.
  final SessionService? session;

  /// Injection point for tests: a fake wrapping a fake Supabase call
  /// instead of the real SDK. Null in the app. Threaded straight through
  /// to [MembershipCard].
  final ProfileRepository? profileRepository;

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
              const SettingsHeader(title: 'settings'),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                  children: [
                    MembershipCard(
                      session: session,
                      isPro: isPro,
                      profileRepository: widget.profileRepository,
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
                    _CustomisationSection(
                      isPro: isPro,
                      onLocked: _busy ? null : _upgrade,
                    ),
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

/// The one row that leads to [CustomisationPage] — sixteen launcher
/// icons across three groups, plus (today) nothing else, though the
/// label leaves room for whatever else "how the app looks" grows to
/// mean. A "cactus pro" feature like `remember`/`recommend`: free
/// readers see the row faded rather than hidden — same
/// discoverability-without-access `HomePage` gives those two commands —
/// and tapping it opens the paywall instead of the page.
class _CustomisationSection extends StatelessWidget {
  const _CustomisationSection({required this.isPro, required this.onLocked});

  final bool isPro;

  /// Opens the paywall. Null while a subscription action is already in
  /// flight elsewhere on this screen, same guard every other row here
  /// uses.
  final VoidCallback? onLocked;

  void _open(BuildContext context) {
    AppHaptics.selection();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'customisation'),
        builder: (_) => const CustomisationPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final row = SettingsRow(
      icon: Icons.palette_outlined,
      label: 'themes and icons',
      onTap: isPro ? () => _open(context) : onLocked,
    );

    return SettingsSection(
      title: 'customisation',
      rows: [isPro ? row : Opacity(opacity: 0.4, child: row)],
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
