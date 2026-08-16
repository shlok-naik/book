import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';

/// Floating pill tab bar. Profile / streak / library share the wide left
/// pill; "+" gets its own circle, set apart, as the primary action.
///
/// Base (always present, selection never changes it): a white pill/circle
/// with a smaller accent-tinted pill/circle inset 2px inside it. Icons
/// sit on that tint. Selecting one layers a solid accent circle + white
/// icon on top — the base underneath stays exactly as it was.
class BottomSwitcher extends StatelessWidget {
  const BottomSwitcher({
    super.key,
    required this.index,
    required this.onChanged,
  });

  final int index;
  final ValueChanged<int> onChanged;

  static const _groupIcons = [
    Icons.person_outline,
    Icons.local_fire_department_outlined,
    Icons.menu_book_outlined,
  ];
  static const _addIndex = 3;

  /// White shape → tinted shape gap ("3px smaller in every direction").
  static const _tintInset = 3.0;
  static const _contentHeight = 56.0;
  static const _outerHeight = _contentHeight + _tintInset * 2;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Base(
          colors: colors,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _groupIcons.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: _contentHeight,
                    child: _SwitcherItem(
                      icon: _groupIcons[i],
                      selected: index == i,
                      onTap: () => onChanged(i),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: _outerHeight,
          child: _Base(
            colors: colors,
            child: _SwitcherItem(
              icon: Icons.add,
              selected: index == _addIndex,
              onTap: () => onChanged(_addIndex),
            ),
          ),
        ),
      ],
    );
  }
}

/// The white pill/circle with its inset accent-tinted twin — unchanging
/// regardless of what's selected inside it.
class _Base extends StatelessWidget {
  const _Base({required this.colors, required this.child});

  final AppColors colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: BottomSwitcher._outerHeight,
      padding: const EdgeInsets.all(BottomSwitcher._tintInset),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: [
          BoxShadow(
            color: colors.primaryText.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.accent.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: child,
      ),
    );
  }
}

class _SwitcherItem extends StatelessWidget {
  const _SwitcherItem({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  static const _selectedSize = 48.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: SizedBox(
        height: BottomSwitcher._contentHeight,
        child: Center(
          child: selected
              ? Container(
                  width: _selectedSize,
                  height: _selectedSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: colors.accent, shape: BoxShape.circle),
                  child: Icon(icon, size: 26, color: Colors.white),
                )
              : Icon(icon, size: 26, color: colors.accent),
        ),
      ),
    );
  }
}
