import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/auth/session_service.dart';
import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/profile_repository.dart';
import '../../domain/profile_exception.dart';
import '../pages/email_sheet.dart';

/// The settings screen's own "cactus" card — a flat membership card,
/// not another settings row: the wordmark and a PRO badge on top, when
/// the account was created underneath, and the email address (or a
/// prompt to add one) below that. No photo, no name field — reading the
/// card top to bottom is the whole account.
///
/// The email line is the *only* way to reach [showEmailSheet] now: the
/// settings screen's old "account" section — a read-only email row plus
/// a separate "change email" row — is gone, folded into this one
/// tappable line. It's also where "sign out" used to sit in spirit: the
/// uid *is* the shelf, so ending a session would lose a library rather
/// than protect one — changing the address it answers to is what a
/// reader actually wants here. See `SessionService.signOut`.
class MembershipCard extends StatefulWidget {
  const MembershipCard({
    super.key,
    required this.session,
    required this.isPro,
    this.profileRepository,
  });

  final SessionService session;
  final bool isPro;

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
  /// Null before the fetch resolves, and again if it failed; either way
  /// the row just doesn't render rather than blocking the rest of the
  /// card on it.
  DateTime? _joinedAt;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final userId = widget.session.userId;
    if (userId == null) return;
    try {
      final joinedAt = await _profiles.fetchJoinedAt(userId);
      if (!mounted) return;
      setState(() => _joinedAt = joinedAt);
    } on ProfileException catch (error) {
      AppLogger.error(
        'MembershipCard',
        'Could not load the profile.',
        error: error,
      );
    }
  }

  /// Both account rows used to lead here; now this line is the only one
  /// that does. Same sheet, same two Supabase calls either way — see
  /// [showEmailSheet].
  Future<void> _editEmail() async {
    final verified = await showEmailSheet(context, session: widget.session);
    if (verified == true && mounted) setState(() {});
  }

  /// `m.d.yy`, no leading zeros — matches the streak journal's own date
  /// label, the only other place in the app that spells a date this way.
  static String _dateLabel(DateTime date) {
    final local = date.toLocal();
    final year = (local.year % 100).toString().padLeft(2, '0');
    return '${local.month}.${local.day}.$year';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final session = widget.session;
    final joinedAt = _joinedAt;

    // The panel flips between black and white with the theme rather
    // than following the app's own surface tones — a membership card
    // is meant to read as its own object, not blend into the page
    // behind it. `onPanel` is what sits on top of it.
    final panel = colors.primaryText;
    final onPanel = colors.background;
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isLight ? 0.16 : 0.5),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: ColoredBox(
              color: panel,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.md,
                    ),
                    child: Column(
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
                        if (joinedAt != null) ...[
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            'member since',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                              color: onPanel.withValues(alpha: 0.65),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _dateLabel(joinedAt),
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: onPanel,
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.md),
                        _EmailLine(
                          session: session,
                          onPanel: onPanel,
                          onTap: _editEmail,
                        ),
                      ],
                    ),
                  ),
                  // The signature strip — the same accent every other
                  // "this is the one thing that matters here" mark in
                  // the app uses (the checkmark on a logged command,
                  // the selected pricing card), laid flat along the
                  // bottom.
                  Container(height: 14, color: colors.accent),
                ],
              ),
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
              style: GoogleFonts.inter(
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

/// The email line, styled as a small pill "join" button while the shelf
/// has no address yet, and as plain (but still tappable) text once one
/// is linked — a button invites the reader to add something; a fact
/// doesn't need to shout.
class _EmailLine extends StatelessWidget {
  const _EmailLine({
    required this.session,
    required this.onPanel,
    required this.onTap,
  });

  final SessionService session;
  final Color onPanel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final anonymous = session.isAnonymous;

    return Semantics(
      button: true,
      label: anonymous
          ? 'Back up with email'
          : 'Change email, currently ${session.email}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: anonymous
            ? Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: onPanel.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.mail_outline, size: 14, color: onPanel),
                    const SizedBox(width: 6),
                    Text(
                      'add email',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: onPanel,
                      ),
                    ),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        session.email!,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: onPanel,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.edit_outlined,
                      size: 13,
                      color: onPanel.withValues(alpha: 0.7),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// A small "PRO" mark, colored as the inverse of whatever panel it sits
/// on rather than fixed colors, so it stays readable whether the panel
/// is the light or the dark side of the theme swap.
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
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: foreground,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
