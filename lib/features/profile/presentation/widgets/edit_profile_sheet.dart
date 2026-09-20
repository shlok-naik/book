import 'package:flutter/material.dart';

import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/profile_identity.dart';
import '../profile_identity_controller.dart';

/// Asks for the reader's name — the profile screen's "edit name". A name is
/// required; the field is the same one onboarding opens with.
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
  late final _displayName = TextEditingController(
    text: ProfileIdentityController.identity.value.displayName ?? '',
  );

  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final error = await ProfileIdentityController.save(
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
              ProfileNameField(controller: _displayName, onSubmit: _save),
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

/// The name field, shared by this sheet and onboarding's first question so
/// the two ask in the same way.
class ProfileNameField extends StatelessWidget {
  const ProfileNameField({super.key, required this.controller, this.onSubmit});

  final TextEditingController controller;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return TextField(
      key: const ValueKey('profile-display-name-field'),
      controller: controller,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.done,
      maxLength: ProfileNames.displayNameMax,
      style: context.fonts.interface(fontSize: 16, color: colors.primaryText),
      onSubmitted: onSubmit == null ? null : (_) => onSubmit!(),
      decoration: InputDecoration(
        labelText: 'your name',
        labelStyle: context.fonts.interface(
          fontSize: 13,
          color: colors.secondaryText,
        ),
        filled: true,
        fillColor: colors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    );
  }
}
