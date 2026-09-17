import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/profile_identity.dart';
import '../profile_identity_controller.dart';

/// Asks for the reader's `@username` and display name — the profile tab's
/// "edit profile", and the same fields onboarding offers. Both are
/// optional: a reader who wants to be nobody in particular stays nobody in
/// particular, and the shelf works either way.
Future<void> showEditProfileSheet(BuildContext context) {
  final colors = context.colors;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.surface,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (_) => const _EditProfileSheet(),
  );
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet();

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final _username = TextEditingController(
    text: ProfileIdentityController.identity.value.username ?? '',
  );
  late final _displayName = TextEditingController(
    text: ProfileIdentityController.identity.value.displayName ?? '',
  );

  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final error = await ProfileIdentityController.save(
      username: _username.text,
      displayName: _displayName.text,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
    });
    if (error != null) {
      AppHaptics.rejected();
      return;
    }
    AppHaptics.accepted();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'your profile',
                  style: context.fonts.interface(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ProfileNameFields(
                username: _username,
                displayName: _displayName,
                onSubmit: _save,
              ),
              if (_error case final error?) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  error,
                  style: context.fonts.body(
                    fontSize: 13,
                    color: colors.primaryText,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                key: const ValueKey('edit-profile-save'),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.background,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _saving ? null : _save,
                child: Text(
                  'save',
                  style: context.fonts.interface(fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The two name fields, shared by this sheet and onboarding's account
/// screen so the two ask for the same things in the same way.
class ProfileNameFields extends StatelessWidget {
  const ProfileNameFields({
    super.key,
    required this.username,
    required this.displayName,
    this.onSubmit,
  });

  final TextEditingController username;
  final TextEditingController displayName;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = context.fonts.interface(
      fontSize: 16,
      color: colors.primaryText,
    );

    InputDecoration decoration(String label, {String? prefix}) =>
        InputDecoration(
          labelText: label,
          prefixText: prefix,
          prefixStyle: style,
          labelStyle: context.fonts.interface(
            fontSize: 13,
            color: colors.secondaryText,
          ),
          filled: true,
          fillColor: colors.background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('profile-display-name-field'),
          controller: displayName,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          maxLength: ProfileNames.displayNameMax,
          style: style,
          decoration: decoration('your name'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          key: const ValueKey('profile-username-field'),
          controller: username,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          maxLength: ProfileNames.usernameMax,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_.@]')),
          ],
          style: style,
          onSubmitted: onSubmit == null ? null : (_) => onSubmit!(),
          decoration: decoration('username', prefix: '@'),
        ),
      ],
    );
  }
}
