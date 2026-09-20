import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/auth/session_service.dart';
import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../profile/domain/profile_identity.dart';
import '../../data/profile_repository.dart';
import '../pages/email_sheet.dart';
import '../pages/library_conflict_page.dart';

/// Links an email to this device's account, or changes the one it has —
/// what settings' profile row does. Resolves true when the library on this
/// device was swapped for the email account's (a second device), so the
/// caller can reload whatever it shows about the account.
Future<bool> editAccountEmail(
  BuildContext context, {
  required SessionService session,
  String? initialEmail,
}) async {
  final result = await showEmailSheet(
    context,
    session: session,
    initialEmail: initialEmail,
  );
  if (result == null || !context.mounted) return false;
  final existing = result.existingAccount;
  if (existing == null) return false;
  await openLibraryConflict(context, session: session, account: existing);
  return true;
}

/// The settings screen's own "cactus" card — a flat membership card,
/// not another settings row: the wordmark and a PRO badge on top, when
/// the account was created underneath, and — once one is linked — the
/// email address below that, over a few low-opacity accent waves
/// washing across the bottom. No photo, no name field — reading the
/// card top to bottom is the whole account.
///
/// The panel is white in light mode and near-black in dark mode —
/// following the app's own `background` token directly, the same
/// direction every other surface in the app already goes, rather than
/// inverting it. The card still reads as its own object because of the
/// shadow, the border-radius and the wave, not because its color
/// fights the theme.
///
/// The card only *shows* the account. Linking or changing the email is
/// settings' profile row ([editAccountEmail]) — a plain, labelled button a
/// reader can find, rather than a pill on a card they had to guess was
/// tappable. There is still no "sign out": the uid *is* the shelf, so
/// ending a session would lose a library rather than protect one.
class MembershipCard extends StatefulWidget {
  const MembershipCard({
    super.key,
    required this.session,
    required this.isPro,
    this.profileRepository,
    this.identity = ProfileIdentity.empty,
  });

  final SessionService session;
  final bool isPro;

  /// The reader's name, shown over the join date once they have set it. Empty by default — the card works without one.
  final ProfileIdentity identity;

  /// Injection point for tests: a fake wrapping a fake Supabase call
  /// instead of the real SDK. Null in the app.
  final ProfileRepository? profileRepository;

  @override
  State<MembershipCard> createState() => _MembershipCardState();
}

class _MembershipCardState extends State<MembershipCard> {
  late final ProfileRepository _profiles =
      widget.profileRepository ?? const ProfileRepository();

  /// When this account was created — the card's "member since" line.
  /// Null both before the fetch resolves and if it failed; [_loading]
  /// is what tells those two apart, since the "member since" row itself
  /// always renders (see [build]) — it never used to, and the fetch
  /// popping it in a beat after the card's first frame made the whole
  /// card visibly grow. Keeping the row's height constant from frame
  /// one and only swapping the value trades that jump for a loading
  /// placeholder instead.
  DateTime? _joinedAt;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final userId = widget.session.userId;
    // No `setState` here: this branch runs synchronously inside
    // `initState`, before the first build — a session without a uid at
    // all is not a state this card can render sensibly regardless, so
    // it just stays on the loading placeholder rather than risk calling
    // `setState` too early.
    if (userId == null) return;
    try {
      final joinedAt = await _profiles.fetchJoinedAt(userId);
      if (!mounted) return;
      setState(() {
        _joinedAt = joinedAt;
        _loading = false;
      });
    } on Object catch (error, stackTrace) {
      // Any failure, not just a ProfileException: an SDK that was never
      // configured throws outright, and a card that can't show a join date
      // must still be a card rather than an error in the framework.
      AppLogger.warning(
        'MembershipCard',
        'Could not load the profile.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// `m.d.yy`, no leading zeros — matches the streak journal's own date
  /// label, the only other place in the app that spells a date this way.
  static String _dateLabel(DateTime date) {
    final local = date.toLocal();
    final year = (local.year % 100).toString().padLeft(2, '0');
    return '${local.month}.${local.day}.$year';
  }

  /// The card's outline — see the comment where it's used. Resolved to an
  /// opaque color (blended onto the panel) so the 1.5px stroke doesn't
  /// double up where it overlaps the panel's own anti-aliased edge.
  static Color _outline(AppColors colors, {required bool isLight}) {
    return Color.alphaBlend(
      colors.primaryText.withValues(alpha: isLight ? 1 : 0.55),
      colors.background,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final session = widget.session;
    final joinedAt = _joinedAt;
    final isLight = Theme.of(context).brightness == Brightness.light;

    // The panel follows the app's own background token directly —
    // white in light mode, near-black in dark — rather than inverting
    // it. `onPanel` is what sits on top of it.
    final panel = colors.background;
    final onPanel = colors.primaryText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            // A drawn, cut-out ink edge rather than just a soft drop
            // shadow. It used to be a hardcoded `Colors.black`, which in
            // dark mode is near-invisible against a charcoal page (and a
            // shadow can't separate dark-on-dark either), so the card
            // blended straight into the settings background. The
            // primary-text token contrasts in both themes: ink on cream,
            // and — softened so it doesn't glare — soft white on charcoal.
            border: Border.all(
              color: _outline(colors, isLight: isLight),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isLight ? 0.14 : 0.5),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: panel)),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _WavePainter(color: colors.accent),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'cactus',
                            style: GoogleFonts.ebGaramond(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: onPanel,
                            ),
                          ),
                          const Spacer(),
                          if (widget.isPro)
                            _ProBadge(background: onPanel, foreground: panel),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (widget.identity.displayName case final name?)
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.fonts.interface(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: onPanel,
                          ),
                        ),
                      if (!widget.identity.isEmpty)
                        const SizedBox(height: AppSpacing.md),
                      Text(
                        'member since',
                        style: context.fonts.body(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                          color: onPanel.withValues(alpha: 0.65),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        // The label above is never conditional on the
                        // fetch any more — only the value is, so the
                        // card's height is settled on the very first
                        // frame instead of growing once the real date
                        // lands a beat later.
                        _loading
                            ? '···'
                            : (joinedAt == null ? '—' : _dateLabel(joinedAt)),
                        style: context.fonts.interface(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: onPanel,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      if (session.email case final email?
                          when !session.isAnonymous)
                        _EmailLine(email: email, onPanel: onPanel, panel: panel)
                      else
                        // Keeps the wave under the same stretch of card
                        // whether or not there's an email to sit on it.
                        const SizedBox(height: _EmailLine.height),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (session.isAnonymous) ...[
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              'Your shelf lives on this device only. Add an email and it '
              'follows you to the next one.',
              style: context.fonts.body(
                fontSize: 12,
                height: 1.5,
                color: colors.secondaryText,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Three low-opacity accent bands, each its own sine wave, layered so
/// they wash across the bottom third of the card like water rather than
/// sitting as one flat stripe — the "signature strip" redrawn as
/// something with a little motion to it instead of a straight line.
/// Painted, not an image or a clipped SVG, so it recolors instantly
/// with the theme's own accent and never needs an asset.
class _WavePainter extends CustomPainter {
  const _WavePainter({required this.color});

  final Color color;

  static const _bands = [
    // (baseline as a fraction of height, amplitude, opacity, phase)
    (0.62, 10.0, 0.10, 0.0),
    (0.74, 8.0, 0.14, 1.9),
    (0.86, 7.0, 0.20, 3.6),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final (baselineFactor, amplitude, alpha, phase) in _bands) {
      final baseline = size.height * baselineFactor;
      final paint = Paint()..color = color.withValues(alpha: alpha);
      final path = Path()..moveTo(0, size.height);
      path.lineTo(0, baseline);
      const steps = 32;
      for (var i = 0; i <= steps; i++) {
        final x = size.width * i / steps;
        final y =
            baseline + amplitude * math.sin((i / steps * 2 * math.pi) + phase);
        path.lineTo(x, y);
      }
      path.lineTo(size.width, size.height);
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// The linked email, on a solid backing chip so the waves behind it
/// never fight its legibility. Not tappable — see [MembershipCard].
class _EmailLine extends StatelessWidget {
  const _EmailLine({
    required this.email,
    required this.onPanel,
    required this.panel,
  });

  final String email;
  final Color onPanel;
  final Color panel;

  /// The chip's height, reserved even when there's no email yet.
  static const height = 26.0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Email, $email',
      excludeSemantics: true,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: panel.withValues(alpha: 0.82),
          border: Border.all(color: onPanel.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mail_outline, size: 14, color: onPanel),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                email,
                style: context.fonts.body(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: onPanel,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small "PRO" mark, colored as the inverse of whatever panel it sits
/// on rather than fixed colors, so it stays readable whether the panel
/// is the light or the dark side of the theme.
class _ProBadge extends StatelessWidget {
  const _ProBadge({required this.background, required this.foreground});

  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        'PRO',
        style: context.fonts.body(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: foreground,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
