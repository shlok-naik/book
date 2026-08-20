import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../library/presentation/pages/library_page.dart';
import '../../../logging/presentation/pages/home_page.dart';
import '../../../profile/presentation/pages/profile_page.dart';
import '../../../streaks/presentation/pages/streaks_page.dart';
import '../widgets/bottom_switcher.dart';

/// Hosts the four top-level pages — profile, streaks, library, and the
/// log — and switches between them with a floating glass tab bar.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  /// The "+" / log page is the default screen.
  int _index = 3;

  static const _pages = [
    ProfilePage(),
    StreaksPage(),
    LibraryPage(),
    HomePage(),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Stack(
      children: [
        IndexedStack(index: _index, children: _pages),
        Positioned(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          bottom: AppSpacing.md,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BottomSwitcher(
                  index: _index,
                  onChanged: (i) => setState(() => _index = i),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'cactus',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 15,
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
