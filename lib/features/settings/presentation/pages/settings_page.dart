import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show CustomerInfo;

import '../../../../core/auth/session_scope.dart';
import '../../../../core/auth/session_service.dart';
import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/purchases/plan_controller.dart';
import '../../../../core/purchases/purchases_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../goals/presentation/goal_scope.dart';
import '../../../goals/presentation/widgets/goal_sheet.dart';
import '../../../library/presentation/library_scope.dart';
import '../../../library/presentation/series_tile_style_controller.dart';
import '../../../library_transfer/presentation/library_exporter.dart';
import '../../../library_transfer/presentation/pages/import_page.dart';
import '../../../logging/presentation/parser_mode_controller.dart';
import '../../../memory/presentation/pages/memory_page.dart';
import '../../../paywall/presentation/pages/paywall_page.dart';
import '../../../search/domain/reading_taste.dart';
import '../../../search/presentation/reading_tastes_controller.dart';
import '../../../search/presentation/widgets/reading_tastes_picker.dart';
import '../../../shell/presentation/start_page_controller.dart';
import '../../data/profile_repository.dart';
import '../widgets/membership_card.dart';
import '../widgets/settings_header.dart';
import '../widgets/settings_section.dart';
import 'commands_page.dart';
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
/// date and, once linked, the email `linkEmail` attaches. Under it the
/// **profile** section holds what's the reader's own: linking (or
/// changing) that email, and their reading memory.
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
    this.exporter,
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

  /// Injection point for tests: a fake that doesn't open a share sheet.
  final LibraryExporter? exporter;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final PurchasesService _purchases =
      widget.purchases ?? const PurchasesService();

  CustomerInfo? _info;
  bool _busy = false;

  /// Bumped when linking an email swapped this device's library for the
  /// email account's, remounting [MembershipCard] so it reloads the new
  /// account's join date.
  int _accountVersion = 0;
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
    PlanController.isPro.addListener(_onPlanChanged);
    _refresh();
  }

  @override
  void dispose() {
    PlanController.isPro.removeListener(_onPlanChanged);
    super.dispose();
  }

  /// The pro-gated rows below read [PlanController.isPro], so a plan
  /// change anywhere (a purchase pushed from another device) redraws them.
  void _onPlanChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    try {
      final info = await _purchases.customerInfo;
      if (!mounted) return;
      setState(() => _info = info);
      // A fresh read here — after a purchase, a restore, or Customer
      // Center — is the newest word on the entitlement; hand it to the
      // app-wide flag too rather than leaving the other tabs to wait for
      // RevenueCat's listener. Only for the real SDK — an injected fake
      // is a test, and must not leak into the global flag the next test
      // reads.
      if (widget.purchases == null) {
        PlanController.updateEntitlement(_purchases.isPro(info));
      }
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
      setState(() => _error = "Couldn't check subscription.");
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

  /// Opens the paywall on the chapter for whichever locked row was tapped
  /// — see [PaywallFeature].
  Future<void> _upgrade([
    PaywallFeature feature = PaywallFeature.general,
  ]) async {
    await showPaywallPopup(
      context,
      purchases: widget.purchases,
      feature: feature,
    );
    // A purchase made in there is invisible to this page otherwise — the
    // card above would still say "free plan" until the next launch.
    if (mounted) await _refresh();
  }

  Future<void> _editEmail() async {
    AppHaptics.selection();
    final swapped = await editAccountEmail(context, session: _session);
    if (!mounted) return;
    setState(() {
      if (swapped) _accountVersion++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final info = _info;
    // Two different questions. [isPro] is "does this account actually
    // hold a subscription" — the card's PRO badge and the "get cactus
    // pro" row must never claim one that the debug override faked.
    // [unlocked] is "should pro features open", which is what every
    // gated row asks, and matches every other gate in the app.
    final isPro = info != null && _purchases.isPro(info);
    final unlocked = isPro || PlanController.isPro.value;
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
                      key: ValueKey(_accountVersion),
                      session: session,
                      isPro: isPro,
                      profileRepository: widget.profileRepository,
                    ),
                    if (error != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        error,
                        style: context.fonts.body(
                          fontSize: 13,
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    _ProfileSection(
                      anonymous: session.isAnonymous,
                      memoryUnlocked: unlocked,
                      onEmail: _busy ? null : _editEmail,
                      onOpenMemory: () {
                        AppHaptics.selection();
                        unawaited(
                          openMemoryPage(context, purchases: widget.purchases),
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    SettingsSection(
                      title: 'cactus pro',
                      rows: [
                        if (!isPro)
                          SettingsRow(
                            icon: Icons.auto_awesome,
                            label: 'get cactus pro',
                            onTap: _busy ? null : () => _upgrade(),
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
                    const _ReadingSection(),
                    const SizedBox(height: AppSpacing.lg),
                    _LibraryDataSection(
                      exporter: widget.exporter,
                      isPro: unlocked,
                      onLocked: _busy
                          ? null
                          : () => _upgrade(PaywallFeature.expression),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const _HelpSection(),
                    const SizedBox(height: AppSpacing.lg),
                    const _AppearanceSection(),
                    const SizedBox(height: AppSpacing.lg),
                    const _StartPageSection(),
                    const SizedBox(height: AppSpacing.lg),
                    _CustomisationSection(
                      isPro: unlocked,
                      onLocked: _busy
                          ? null
                          : () => _upgrade(PaywallFeature.customisation),
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

/// What's the reader's own, under the card that shows the account:
/// linking an email to it (the plain, labelled way in — the card itself
/// isn't tappable) and their reading memory.
///
/// Memory is cactus pro, but the row is never faded: `MemoryPage` gates its
/// own contents and shows a free reader a preview of what it holds, which
/// says more than a faded row would.
class _ProfileSection extends StatelessWidget {
  const _ProfileSection({
    required this.anonymous,
    required this.memoryUnlocked,
    required this.onEmail,
    required this.onOpenMemory,
  });

  final bool anonymous;
  final bool memoryUnlocked;
  final VoidCallback? onEmail;
  final VoidCallback onOpenMemory;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: 'profile',
      rows: [
        SettingsRow(
          icon: anonymous ? Icons.mail_outline : Icons.edit_outlined,
          label: anonymous ? 'link your email' : 'change email',
          onTap: onEmail,
        ),
        ValueListenableBuilder<List<ReadingTaste>>(
          valueListenable: ReadingTastesController.tastes,
          builder: (context, tastes, _) => SettingsRow(
            key: const ValueKey('profile-reading-tastes'),
            icon: Icons.local_library_outlined,
            label: 'reading tastes',
            value: switch (tastes.length) {
              0 => 'none yet',
              1 => tastes.single.label,
              final n => '$n picked',
            },
            onTap: () {
              AppHaptics.selection();
              unawaited(showReadingTastesSheet(context));
            },
          ),
        ),
        SettingsRow(
          icon: Icons.bookmark_border,
          label: 'memory',
          value: memoryUnlocked ? null : 'pro',
          onTap: onOpenMemory,
        ),
      ],
    );
  }
}

/// The reader's yearly goal — the same value onboarding asked for and the
/// stats page shows progress against. Free.
class _ReadingSection extends StatelessWidget {
  const _ReadingSection();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final goals = GoalScope.of(context);
    final goal = goals.goal;
    return SettingsSection(
      title: 'reading',
      rows: [
        SettingsRow(
          icon: Icons.flag_outlined,
          label: 'yearly goal',
          value: !goals.isLoaded
              ? null
              : goal == null
              ? 'not set'
              : '$goal ${goal == 1 ? 'book' : 'books'}',
          onTap: () {
            AppHaptics.selection();
            showGoalSheet(context);
          },
        ),
        ValueListenableBuilder<bool>(
          valueListenable: SeriesTileStyleController.patchwork,
          builder: (context, patchwork, _) => SettingsRow(
            icon: Icons.grid_view_outlined,
            label: 'series tiles',
            trailing: Switch(
              value: patchwork,
              activeThumbColor: colors.accent,
              onChanged: (value) {
                AppHaptics.selection();
                reportingFailure(
                  SeriesTileStyleController.select(value),
                  source: 'SettingsPage',
                  message: 'Could not save the series tile style.',
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Getting a library out (CSV, free) and in (a Goodreads import, cactus
/// pro — replaces the whole library, so it's gated the same "faded, never
/// hidden" way [_CustomisationSection] gates themes and icons).
class _LibraryDataSection extends StatefulWidget {
  const _LibraryDataSection({
    this.exporter,
    required this.isPro,
    required this.onLocked,
  });

  final LibraryExporter? exporter;
  final bool isPro;
  final VoidCallback? onLocked;

  @override
  State<_LibraryDataSection> createState() => _LibraryDataSectionState();
}

class _LibraryDataSectionState extends State<_LibraryDataSection> {
  bool _exporting = false;
  String? _message;

  Future<void> _export() async {
    AppHaptics.selection();
    setState(() {
      _exporting = true;
      _message = null;
    });
    final error = await (widget.exporter ?? const LibraryExporter()).export(
      LibraryScope.read(context),
    );
    if (!mounted) return;
    setState(() {
      _exporting = false;
      _message = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final message = _message;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'your library',
          rows: [
            SettingsRow(
              icon: Icons.ios_share,
              label: _exporting ? 'exporting…' : 'export as csv',
              onTap: _exporting ? null : _export,
            ),
            widget.isPro
                ? SettingsRow(
                    icon: Icons.upload_file_outlined,
                    label: 'import from goodreads',
                    onTap: () {
                      AppHaptics.selection();
                      openGoodreadsImport(context);
                    },
                  )
                : Opacity(
                    opacity: 0.4,
                    child: SettingsRow(
                      icon: Icons.upload_file_outlined,
                      label: 'import from goodreads',
                      onTap: widget.onLocked,
                    ),
                  ),
          ],
        ),
        if (message != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            style: context.fonts.body(
              fontSize: 13,
              color: colors.secondaryText,
            ),
          ),
        ],
      ],
    );
  }
}

/// The one row that leads to [CommandsPage] — every text command, for a
/// reader who has forgotten one. Free, unlike customisation: knowing what
/// you can type is part of using the app at all.
class _HelpSection extends StatelessWidget {
  const _HelpSection();

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: 'help',
      rows: [
        SettingsRow(
          icon: Icons.terminal,
          label: 'commands',
          onTap: () {
            AppHaptics.selection();
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                settings: const RouteSettings(name: 'commands'),
                builder: (_) => const CommandsPage(),
              ),
            );
          },
        ),
      ],
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

/// Which tab the app opens on — three mutually exclusive choices, built
/// exactly like [_AppearanceSection].
class _StartPageSection extends StatelessWidget {
  const _StartPageSection();

  static const _icons = {
    StartPage.add: Icons.add,
    StartPage.search: Icons.search,
    StartPage.library: Icons.menu_book_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StartPage>(
      valueListenable: StartPageController.page,
      builder: (context, current, _) {
        return SettingsSection(
          title: 'starting page',
          rows: [
            for (final page in StartPage.values)
              SettingsRow(
                icon: _icons[page]!,
                label: page.label,
                trailing: _Check(selected: current == page),
                onTap: () {
                  if (current == page) return;
                  AppHaptics.selection();
                  reportingFailure(
                    StartPageController.select(page),
                    source: 'SettingsPage',
                    message: 'Could not save the starting page.',
                  );
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

/// Debug-only: which parser the add tab uses — classic commands, the
/// on-device beta parser, or pro AI — as three choices like
/// [_AppearanceSection]. Never compiled into a release build, where the
/// plan decides (see [ParserModeController]).
class _DebugSection extends StatelessWidget {
  const _DebugSection();

  static const _icons = {
    ParserMode.classic: Icons.terminal,
    ParserMode.beta: Icons.science_outlined,
    ParserMode.proAi: Icons.auto_awesome,
  };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ParserMode?>(
      valueListenable: ParserModeController.chosen,
      builder: (context, chosen, _) {
        final current = chosen ?? ParserModeController.planDefault;
        return SettingsSection(
          title: 'debug · parser',
          rows: [
            for (final mode in ParserMode.values)
              SettingsRow(
                key: ValueKey('parser-mode-${mode.name}'),
                icon: _icons[mode]!,
                label: mode.label,
                trailing: _Check(selected: current == mode),
                onTap: () {
                  if (current == mode) return;
                  AppHaptics.selection();
                  reportingFailure(
                    ParserModeController.select(mode),
                    source: 'SettingsPage',
                    message: 'Could not save the parser mode.',
                  );
                },
              ),
          ],
        );
      },
    );
  }
}
