import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../widgets/command_wall.dart';
import 'natural_language_tutorial_page.dart';
import 'tutorial_step_page.dart';

/// The step right after [AddBookTutorialPage]'s shelf commands: a book can
/// carry the reader's own tags and comments too — and a comment is where
/// the reason for a DNF goes.
///
/// Built exactly like the step before it — a [TutorialStepPage] with a
/// [CommandWall] above the card and a bulleted command list inside it —
/// so the two read as one continuous tutorial, not a page from a different
/// flow. It asks for nothing and has no text field, like every onboarding
/// screen (see `intro_flow_test.dart`).
class TagsCommentsTutorialPage extends StatelessWidget {
  const TagsCommentsTutorialPage({super.key});

  /// Rows for the wall — the same chip style as the step before, showing
  /// tags and comments in use, including a DNF with its reason.
  static const wallRows = [
    [
      'make tag sci-fi',
      'add tag sci-fi Dune',
      'make tag cosy',
      'add tag cosy Emma',
      'add tag "book club" Circe',
      'add tag reread 1984',
    ],
    [
      'add comment "loved the ending" Circe',
      'add comment "slow first half" Dune',
      'add comment "cried twice" The Hobbit',
    ],
    [
      'move Ulysses dnf',
      'add comment "too dense for me right now" Ulysses',
      'add tag maybe-later Ulysses',
    ],
    [
      'add tag classics Emma',
      'add comment "reading with mum" 1984',
      'add tag favourites The Shining',
    ],
  ];

  @override
  Widget build(BuildContext context) {
    return TutorialStepPage(
      topContent: const CommandWall(rows: wallRows),
      heading: 'make every book yours',
      description: const _TutorialCopy(),
      onContinue: () => Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'onboarding_nl_tutorial'),
          builder: (_) => const NaturalLanguageTutorialPage(),
        ),
      ),
    );
  }
}

const _commands = ['add tag <tag> <book>', 'add comment <comment> <book>'];

class _TutorialCopy extends StatelessWidget {
  const _TutorialCopy();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'you can also add tags and comments to any book on your shelf - '
          'tags to group books however you like, and comments to note '
          'anything worth remembering. the commands are:',
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final command in _commands) _CommandLine(command),
        const SizedBox(height: AppSpacing.sm),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'when you mark a book as '),
              TextSpan(
                text: 'dnf',
                style: TextStyle(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const TextSpan(
                text:
                    ' (did not finish), add a comment saying why you stopped '
                    "- so future you knows whether it's worth another try.",
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'ps. tap any book in your library to see and edit its tags and '
          'comments too.',
          style: GoogleFonts.inter(fontStyle: FontStyle.italic),
        ),
      ],
    );
  }
}

/// One line of the command list — identical to the step before's own
/// `_CommandLine`, so the two lists look the same.
class _CommandLine extends StatelessWidget {
  const _CommandLine(this.command);

  final String command;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: TextStyle(color: colors.accent)),
          Expanded(
            child: Text(
              command,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                color: colors.primaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
