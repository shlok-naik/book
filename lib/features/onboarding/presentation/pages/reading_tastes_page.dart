import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../paywall/presentation/widgets/soft_pill_button.dart';
import '../../../search/domain/reading_taste.dart';
import '../../../search/presentation/reading_tastes_controller.dart';
import '../../../search/presentation/widgets/reading_tastes_picker.dart';
import '../widgets/half_sheet_scaffold.dart';
import '../widgets/tour_illustrations.dart';
import 'one_more_thing_page.dart';

/// Asked right after the reading goal: what kinds of books the reader
/// likes. Tapped chips, no typing — and skippable. Saved through
/// [ReadingTastesController], the same state settings' profile section
/// edits, and used for the search tab's recommendations.
class ReadingTastesPage extends StatefulWidget {
  const ReadingTastesPage({super.key});

  @override
  State<ReadingTastesPage> createState() => _ReadingTastesPageState();
}

class _ReadingTastesPageState extends State<ReadingTastesPage> {
  late Set<ReadingTaste> _picked = ReadingTastesController.tastes.value.toSet();

  void _next() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'onboarding_one_more_thing'),
        builder: (_) => const OneMoreThingPage(),
      ),
    );
  }

  Future<void> _save() async {
    await ReadingTastesController.select(_picked);
    if (mounted) _next();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return HalfSheetScaffold(
      showBackButton: true,
      progressStep: 3,
      topContent: const TourIcon(Icons.auto_stories_outlined),
      cardChild: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'what do you like to read?',
            style: GoogleFonts.ebGaramond(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'pick a few — we\'ll recommend books you\'ll like. change them '
            'any time in settings.',
            style: GoogleFonts.inter(
              fontSize: 16,
              height: 1.5,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ReadingTastesPicker(
            selected: _picked,
            onChanged: (next) => setState(() => _picked = next),
          ),
          const SizedBox(height: AppSpacing.lg),
          SoftPillButton(label: 'continue', onPressed: _save),
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            onPressed: _next,
            child: Text(
              'skip for now',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: colors.secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
