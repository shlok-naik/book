import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/auth/session_scope.dart';
import '../../../../core/auth/session_service.dart';
import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/formatting/numbers.dart';
import '../../../../core/purchases/plan_controller.dart';
import '../../../../core/purchases/purchases_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../goals/domain/daily_goal.dart';
import '../../../goals/presentation/daily_goal_controller.dart';
import '../../../library/presentation/library_scope.dart';
import '../../../memory/presentation/pages/memory_page.dart';
import '../../../search/domain/reading_taste.dart';
import '../../../search/presentation/reading_tastes_controller.dart';
import '../../../search/presentation/widgets/reading_tastes_picker.dart';
import '../../../settings/data/profile_repository.dart';
import '../../../settings/presentation/pages/settings_page.dart';
import '../../../settings/presentation/widgets/membership_card.dart';
import '../../../settings/presentation/widgets/settings_header.dart';
import '../../../settings/presentation/widgets/settings_section.dart';
import '../../../streaks/domain/reading_stats.dart';
import '../../domain/profile_identity.dart';
import '../profile_identity_controller.dart';
import '../widgets/edit_profile_sheet.dart';

/// Opens the profile screen — what the avatar in every page's [TopBar]
/// does. The one way it should be pushed, so the route always carries its
/// analytics name.
Future<void> openProfilePage(
  BuildContext context, {
  PurchasesService? purchases,
  SessionService? session,
  ProfileRepository? profileRepository,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'profile'),
      builder: (_) => ProfilePage(
        purchases: purchases,
        session: session,
        profileRepository: profileRepository,
      ),
    ),
  );
}

/// Who the reader is: the account card, their name, the
/// email that backs the shelf up, their reading tastes, their memory and
/// their year — and one row into [SettingsPage] for everything that isn't
/// about them.
///
/// This is where the account lives now. The gear that used to sit in every
/// page's [TopBar] is an avatar instead, and settings itself no longer
/// carries the membership card or a profile section: one screen answers
/// "who am I", the other "how does the app behave".
class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    this.purchases,
    this.session,
    this.profileRepository,
  });

  /// Injection points for tests; null in the app.
  final PurchasesService? purchases;
  final SessionService? session;
  final ProfileRepository? profileRepository;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  /// Bumped when linking an email swapped this device's library for the
  /// email account's, remounting the card so it reloads the new account.
  int _accountVersion = 0;
  bool _busy = false;

  late final PurchasesService _purchases =
      widget.purchases ?? const PurchasesService();

  /// Whether the store says this account holds the subscription — what the
  /// card's PRO badge reads. Fails closed: a store that can't be reached
  /// shows no badge rather than claiming one.
  bool _isPro = PlanController.isEntitled;

  @override
  void initState() {
    super.initState();
    unawaited(_readEntitlement());
  }

  Future<void> _readEntitlement() async {
    bool entitled;
    try {
      entitled = _purchases.isPro(await _purchases.customerInfo);
    } on Object {
      entitled = PlanController.isEntitled;
    }
    if (!mounted || entitled == _isPro) return;
    setState(() => _isPro = entitled);
  }

  SessionService get _session => widget.session ?? SessionScope.of(context);

  Future<void> _editEmail() async {
    if (_busy) return;
    AppHaptics.selection();
    setState(() => _busy = true);
    try {
      final swapped = await editAccountEmail(context, session: _session);
      if (!mounted) return;
      setState(() {
        if (swapped) _accountVersion++;
      });
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'ProfilePage',
        'Editing the email failed.',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final library = LibraryScope.of(context);
    final stats = ReadingStats.forShelf(
      library.books,
      importedAt: library.importedAt,
    );

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Padding(
          // The same gutter and top inset every pushed screen uses, so the
          // heading doesn't shift a pixel from the page underneath.
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SettingsHeader(title: 'profile'),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: ValueListenableBuilder<ProfileIdentity>(
                  valueListenable: ProfileIdentityController.identity,
                  builder: (context, identity, _) => ListView(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                    children: [
                      MembershipCard(
                        key: ValueKey(_accountVersion),
                        session: _session,
                        isPro: _isPro,
                        profileRepository: widget.profileRepository,
                        identity: identity,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _ReadingSummary(stats: stats),
                      const SizedBox(height: AppSpacing.lg),
                      SettingsSection(
                        title: 'you',
                        rows: [
                          SettingsRow(
                            key: const ValueKey('profile-edit'),
                            icon: Icons.badge_outlined,
                            label: 'name',
                            value: identity.displayName ?? 'not set',
                            onTap: () {
                              AppHaptics.selection();
                              unawaited(showEditProfileSheet(context));
                            },
                          ),
                          SettingsRow(
                            key: const ValueKey('profile-email'),
                            icon: _session.isAnonymous
                                ? Icons.mail_outline
                                : Icons.edit_outlined,
                            label: _session.isAnonymous
                                ? 'link your email'
                                : 'change email',
                            onTap: _busy ? null : _editEmail,
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
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      SettingsSection(
                        title: 'your reading',
                        rows: [
                          SettingsRow(
                            key: const ValueKey('profile-memory'),
                            icon: Icons.bookmark_border,
                            label: 'memory',
                            onTap: () {
                              AppHaptics.selection();
                              unawaited(
                                openMemoryPage(
                                  context,
                                  purchases: widget.purchases,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      SettingsSection(
                        title: 'app',
                        rows: [
                          SettingsRow(
                            key: const ValueKey('profile-settings'),
                            icon: Icons.settings_outlined,
                            label: 'settings',
                            onTap: () {
                              AppHaptics.selection();
                              unawaited(
                                openSettingsPage(
                                  context,
                                  purchases: widget.purchases,
                                  session: widget.session,
                                  profileRepository: widget.profileRepository,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three numbers from the shelf, so the screen says something about the
/// reader before they tap anything: books this year, the daily streak and
/// pages read. Free — the charts live on the stats tab.
class _ReadingSummary extends StatelessWidget {
  const _ReadingSummary({required this.stats});

  final ReadingStats stats;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DailyGoal>(
      valueListenable: DailyGoalController.goal,
      builder: (context, goal, _) => Row(
        children: [
          _Number(
            label: 'books in ${stats.year}',
            value: '${stats.booksThisYear}',
          ),
          _Number(label: 'day streak', value: '${goal.streak(DateTime.now())}'),
          _Number(
            label: 'pages all time',
            value: formatThousands(stats.pagesAllTime),
          ),
        ],
      ),
    );
  }
}

class _Number extends StatelessWidget {
  const _Number({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Expanded(
      child: Semantics(
        label: '$value $label',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: context.fonts.interface(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: colors.primaryText,
              ),
            ),
            Text(
              label,
              style: context.fonts.body(
                fontSize: 12,
                color: colors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
