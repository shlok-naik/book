import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';

/// Rounded-rect (not full pill) tab bar. Profile / streak / library share
/// the wide left container; "+" gets its own square, set apart, as the
/// primary action.
///
/// Every icon slot follows the same explicit, symmetric ring — identical
/// whether it's an edge icon or a middle one:
///   white → [_tintInset] → tint → [_itemGap] → selection → [_iconInset] → icon
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

  static const _tintInset = AppSpacing.xs;
  static const _itemGap = AppSpacing.xs;
  static const _iconSpacing = AppSpacing.md;
  static const _slotSize = _SwitcherItem.selectedSize;
  static const _outerHeight = _slotSize + (_itemGap + _tintInset) * 2;
  static const _barRadius = AppRadius.lg;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Base(
          colors: colors,
          child: Padding(
            padding: const EdgeInsets.all(_itemGap),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _groupIcons.length; i++) ...[
                  if (i > 0) const SizedBox(width: _iconSpacing),
                  _SwitcherItem(
                    icon: _groupIcons[i],
                    selected: index == i,
                    onTap: () => onChanged(i),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: _iconSpacing),
        _Base(
          colors: colors,
          child: Padding(
            padding: const EdgeInsets.all(_itemGap),
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

/// The white rounded-rect with its inset accent-tinted twin — unchanging
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
        borderRadius: BorderRadius.circular(BottomSwitcher._barRadius),
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
          borderRadius: BorderRadius.circular(AppRadius.md),
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

  static const selectedSize = 54.0;
  static const _iconInset = AppSpacing.sm + 4;
  static const _iconSize = selectedSize - _iconInset * 2;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        width: selectedSize,
        height: selectedSize,
        child: Center(
          child: selected
              ? Container(
                  width: selectedSize,
                  height: selectedSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(icon, size: _iconSize, color: Colors.white),
                )
              : Icon(icon, size: _iconSize, color: colors.accent),
        ),
      ),
    );
  }
}
