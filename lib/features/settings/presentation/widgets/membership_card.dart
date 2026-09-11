import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/auth/session_service.dart';
import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/avatar_picker.dart';
import '../../data/profile_repository.dart';
import '../../domain/profile_exception.dart';
import '../pages/email_sheet.dart';

/// The settings screen's own "cactus" card — a real membership/transit
/// card, not another settings row: a bold wordmark and join date on a
/// solid panel that flips between black and white with the theme, a
/// curved photo box on the right holding the picture, and a signature
/// strip along the bottom. No name field goes with it — the card is
/// deliberately just a photo and the email `linkEmail` already attaches,
/// nothing new to type.
///
/// The avatar is the only way to reach [ProfileRepository.uploadAvatar]
/// — tapping it opens the photo library, and the picked photo shows up
/// immediately, before the upload confirms, the same optimistic-first
/// way every shelf command in this app already works. The email line is
/// now the *only* way to reach [showEmailSheet]: the settings screen's
/// old "account" section — a read-only email row plus a separate
/// "change email" row — is gone, folded into this one tappable line.
/// It's also where "sign out" used to sit in spirit: the uid *is* the
/// shelf, so ending a session would lose a library rather than protect
/// one — changing the address it answers to is what a reader actually
/// wants here. See `SessionService.signOut`.
class MembershipCard extends StatefulWidget {
  const MembershipCard({
    super.key,
    required this.session,
    required this.isPro,
    this.profileRepository,
    this.avatarPicker,
  });

  final SessionService session;
  final bool isPro;

  /// Injection point for tests: a fake wrapping fake storage/profile
  /// calls instead of the real Supabase SDK. Null in the app.
  final ProfileRepository? profileRepository;

  /// Injection point for tests: a fake that hands back canned bytes
  /// instead of opening the real photo library. Null in the app.
  final AvatarPicker? avatarPicker;

  @override
  State<MembershipCard> createState() => _MembershipCardState();
}

class _MembershipCardState extends State<MembershipCard> {
  late final ProfileRepository _profiles =
      widget.profileRepository ?? const ProfileRepository();

  late final AvatarPicker _picker = widget.avatarPicker ?? const AvatarPicker();

  /// Null before the initial fetch resolves, and again if it failed —
  /// either way the avatar just shows its placeholder icon rather than a
  /// spinner or an error banner; a picture that can't load isn't worth
  /// holding up the rest of the card for.
  String? _avatarUrl;

  /// When this account was created — the card's "member since" line.
  /// Null under the same quiet-failure rule as [_avatarUrl]: the row
  /// just doesn't render rather than blocking on it.
  DateTime? _joinedAt;

  /// The just-picked photo, shown the instant it's chosen — optimistic
  /// like every other command in this app. Cleared once the real URL
  /// replaces it, or the upload fails and this reverts to [_avatarUrl].
  Uint8List? _pendingBytes;

  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final userId = widget.session.userId;
    if (userId == null) return;
    try {
      final profile = await _profiles.fetchProfile(userId);
      if (!mounted) return;
      setState(() {
        _avatarUrl = profile.avatarUrl;
        _joinedAt = profile.joinedAt;
      });
    } on ProfileException catch (error) {
      AppLogger.error(
        'MembershipCard',
        'Could not load the profile.',
        error: error,
      );
    }
  }

  Future<void> _pickAvatar() async {
    final userId = widget.session.userId;
    if (userId == null || _uploading) return;

    final PickedAvatar? picked;
    try {
      picked = await _picker.pickFromGallery();
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'MembershipCard',
        'Could not open the photo library.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() => _error = "We couldn't open your photo library.");
      return;
    }
    if (picked == null) return;

    setState(() {
      _pendingBytes = picked!.bytes;
      _uploading = true;
      _error = null;
    });

    try {
      final url = await _profiles.uploadAvatar(
        userId: userId,
        bytes: picked.bytes,
        extension: picked.extension,
      );
      if (!mounted) return;
      setState(() {
        _avatarUrl = url;
        _pendingBytes = null;
        _uploading = false;
      });
    } on ProfileException catch (error) {
      if (!mounted) return;
      setState(() {
        _pendingBytes = null;
        _uploading = false;
        _error = error.message;
      });
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
    final error = _error;
    final joinedAt = _joinedAt;

    // The panel flips between black and white with the theme rather
    // than following the app's own surface tones — a membership card
    // is meant to read as its own object, not blend into the page
    // behind it. `panel` is the big colored area; `onPanel` is what
    // sits on it; `photoBacking` is the lighter box the picture lives
    // in, which is `onPanel`'s own color so the two always contrast.
    final panel = colors.primaryText;
    final onPanel = colors.background;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: _MembershipCardPainter.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: Theme.of(context).brightness == Brightness.light
                      ? 0.16
                      : 0.5,
                ),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: panel),
                ClipPath(
                  clipper: _CardCurveClipper(),
                  child: ColoredBox(color: onPanel),
                ),
                // The signature strip — the same accent every other
                // "this is the one action that matters" mark in the app
                // uses (the checkmark on a logged command, the selected
                // pricing card), here just laid flat along the bottom.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: _MembershipCardPainter.stripHeight,
                    color: colors.accent,
                  ),
                ),
                Positioned(
                  left: AppSpacing.lg,
                  right: 0,
                  top: AppSpacing.md,
                  bottom: _MembershipCardPainter.stripHeight + AppSpacing.md,
                  child: FractionallySizedBox(
                    widthFactor: _MembershipCardPainter.textWidthFactor,
                    alignment: Alignment.topLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'cactus',
                                style: GoogleFonts.ebGaramond(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  height: 1,
                                  color: onPanel,
                                ),
                              ),
                            ),
                            if (widget.isPro) ...[
                              const SizedBox(width: AppSpacing.xs),
                              _ProBadge(background: onPanel, foreground: panel),
                            ],
                          ],
                        ),
                        if (joinedAt != null)
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'member since',
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  height: 1,
                                  letterSpacing: 0.8,
                                  color: onPanel.withValues(alpha: 0.65),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _dateLabel(joinedAt),
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  height: 1,
                                  color: onPanel,
                                ),
                              ),
                            ],
                          ),
                        _EmailLine(
                          session: session,
                          onPanel: onPanel,
                          onTap: _editEmail,
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: AppSpacing.lg,
                  top: AppSpacing.md,
                  bottom: _MembershipCardPainter.stripHeight + AppSpacing.md,
                  child: Center(
                    child: _Avatar(
                      url: _avatarUrl,
                      pendingBytes: _pendingBytes,
                      busy: _uploading,
                      onPanel: onPanel,
                      accent: colors.accent,
                      onTap: _pickAvatar,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              error,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: colors.secondaryText,
              ),
            ),
          ),
        ],
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

/// Layout constants shared between the card's [Container] height and the
/// curve/strip/text-column math that has to agree with it. Named after a
/// painter even though nothing here actually paints, because every one
/// of these numbers exists to keep the hand-drawn parts of the card
/// (the curve, the strip) consistent with the parts Flutter lays out
/// normally.
abstract final class _MembershipCardPainter {
  static const height = 210.0;
  static const stripHeight = 14.0;

  /// How much of the card's width the left-hand text column claims
  /// before the curve/photo area starts — kept under the curve's own
  /// leftmost point ([_CardCurveClipper]) so nothing overlaps it.
  static const textWidthFactor = 0.52;
}

/// The photo box's left edge: a smooth curve bulging toward the card's
/// centre rather than a straight vertical line — the "swoosh" a transit
/// card's photo panel is cut along, redrawn here instead of a plain
/// rectangle.
class _CardCurveClipper extends CustomClipper<Path> {
  const _CardCurveClipper();

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final edgeTop = w * 0.66;
    final edgeMid = w * 0.55;
    final edgeBottom = w * 0.66;

    return Path()
      ..moveTo(edgeTop, 0)
      ..quadraticBezierTo(edgeMid, h / 2, edgeBottom, h)
      ..lineTo(w, h)
      ..lineTo(w, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
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

/// The photo itself — a portrait rectangle like an ID photo, not a
/// circle, sitting in the card's curved cutout — plus a small edit badge
/// that doubles as the busy indicator while a picked photo is uploading.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.url,
    required this.pendingBytes,
    required this.busy,
    required this.onPanel,
    required this.accent,
    required this.onTap,
  });

  final String? url;
  final Uint8List? pendingBytes;
  final bool busy;
  final Color onPanel;
  final Color accent;
  final VoidCallback onTap;

  static const _width = 64.0;
  static const _height = 80.0;
  static const _badgeSize = 22.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bytes = pendingBytes;
    final avatarUrl = url;

    return Semantics(
      button: true,
      label: 'Change profile picture',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: _width + _badgeSize / 2,
          height: _height + _badgeSize / 2,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Container(
                  width: _width,
                  height: _height,
                  decoration: BoxDecoration(
                    border: Border.all(color: onPanel.withValues(alpha: 0.25)),
                  ),
                  // The picked photo takes over the instant it's
                  // chosen — this is the optimistic frame, shown before
                  // the upload has confirmed anything.
                  child: bytes != null
                      ? Image.memory(bytes, fit: BoxFit.cover)
                      : (avatarUrl == null
                            ? Icon(
                                Icons.person_outline,
                                size: 28,
                                color: colors.secondaryText,
                              )
                            : Image.network(
                                avatarUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Icon(
                                  Icons.person_outline,
                                  size: 28,
                                  color: colors.secondaryText,
                                ),
                              )),
                ),
              ),
              Positioned(
                right: -_badgeSize / 4,
                bottom: -_badgeSize / 4,
                child: Container(
                  width: _badgeSize,
                  height: _badgeSize,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: onPanel, width: 2),
                  ),
                  child: busy
                      ? Padding(
                          padding: const EdgeInsets.all(4),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: onPanel,
                          ),
                        )
                      : Icon(Icons.camera_alt, size: 12, color: onPanel),
                ),
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
