import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/auth/session_service.dart';
import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/dotted_background.dart';
import '../../data/avatar_picker.dart';
import '../../data/profile_repository.dart';
import '../../domain/profile_exception.dart';
import '../pages/email_sheet.dart';

/// The settings screen's own "cactus" card, styled like a membership
/// card rather than another row of settings: a profile picture and the
/// email address that backs the shelf up — nothing else. There is no
/// name field anywhere in the app, and this card is deliberately not
/// where one would start.
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

  /// The just-picked photo, shown the instant it's chosen — optimistic
  /// like every other command in this app. Cleared once the real URL
  /// replaces it, or the upload fails and this reverts to [_avatarUrl].
  Uint8List? _pendingBytes;

  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  Future<void> _loadAvatar() async {
    final userId = widget.session.userId;
    if (userId == null) return;
    try {
      final url = await _profiles.fetchAvatarUrl(userId);
      if (!mounted) return;
      setState(() => _avatarUrl = url);
    } on ProfileException catch (error) {
      AppLogger.error(
        'MembershipCard',
        'Could not load the profile picture.',
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final session = widget.session;
    final error = _error;
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: DottedBackground(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: colors.divider),
                boxShadow: isLight
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'cactus',
                        style: GoogleFonts.ebGaramond(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: colors.primaryText,
                        ),
                      ),
                      const Spacer(),
                      if (widget.isPro) const _ProBadge(),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _Avatar(
                        url: _avatarUrl,
                        pendingBytes: _pendingBytes,
                        busy: _uploading,
                        onTap: _pickAvatar,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Semantics(
                          button: true,
                          label: session.isAnonymous
                              ? 'Back up with email'
                              : 'Change email, currently ${session.email}',
                          excludeSemantics: true,
                          child: InkWell(
                            onTap: _editEmail,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.xs,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      session.isAnonymous
                                          ? 'back up with email'
                                          : session.email!,
                                      style: GoogleFonts.inter(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: colors.primaryText,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Icon(
                                    session.isAnonymous
                                        ? Icons.mail_outline
                                        : Icons.edit_outlined,
                                    size: 18,
                                    color: colors.secondaryText,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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

/// The circular photo itself, plus a small edit badge that doubles as
/// the busy indicator while a picked photo is uploading.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.url,
    required this.pendingBytes,
    required this.busy,
    required this.onTap,
  });

  final String? url;
  final Uint8List? pendingBytes;
  final bool busy;
  final VoidCallback onTap;

  static const _size = 56.0;
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
          width: _size + _badgeSize / 2,
          height: _size + _badgeSize / 2,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ClipOval(
                child: SizedBox(
                  width: _size,
                  height: _size,
                  child: ColoredBox(
                    color: colors.background,
                    // The picked photo takes over the instant it's
                    // chosen — this is the optimistic frame, shown
                    // before the upload has confirmed anything.
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
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: _badgeSize,
                  height: _badgeSize,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.surface, width: 2),
                  ),
                  child: busy
                      ? Padding(
                          padding: const EdgeInsets.all(4),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.background,
                          ),
                        )
                      : Icon(
                          Icons.camera_alt,
                          size: 12,
                          color: colors.background,
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

/// Same wordmark badge the paywall's header wears — the same "PRO" is
/// worth recognizing here as the reason it exists.
class _ProBadge extends StatelessWidget {
  const _ProBadge();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.primaryText,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        'PRO',
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: colors.background,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
