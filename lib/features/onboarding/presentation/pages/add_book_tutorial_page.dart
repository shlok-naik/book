import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/onboarding_profile_repository.dart';
import '../../data/session_service.dart';
import '../widgets/command_wall.dart';
import 'natural_language_tutorial_page.dart';
import 'tutorial_step_page.dart';

/// Step 1 of the post-welcome sequence, shown right after the welcome
/// screen: a tilted wall of the log page's own commands, each row
/// scrolling sideways — in place of the screenshot Pushr's equivalent
/// step uses.
///
/// The free-tier half of the tutorial's two steps — the fixed commands
/// a reader can type. [NaturalLanguageTutorialPage] follows with the
/// Pro-tier's natural language instead, kept as its own step rather
/// than more scrolling on this one so each half gets its own
/// illustrating wall above it.
class AddBookTutorialPage extends StatelessWidget {
  const AddBookTutorialPage({
    super.key,
    required this.session,
    required this.profiles,
  });

  final SessionService session;
  final OnboardingProfileRepository profiles;

  @override
  Widget build(BuildContext context) {
    return TutorialStepPage(
      topContent: const CommandWall(),
      heading: 'log books as you read them',
      description: const _TutorialCopy(),
      onContinue: () => Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'onboarding_nl_tutorial'),
          builder: (_) =>
              NaturalLanguageTutorialPage(session: session, profiles: profiles),
        ),
      ),
    );
  }
}

/// The commands a free-tier reader can use — shown as a list.
const _commands = [
  'start <book>',
  'update <book> <page number>',
  'finish <book>',
  'rate <book> <number of stars>',
];

class _TutorialCopy extends StatelessWidget {
  const _TutorialCopy();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'cactus allows you to log your reading using simple commands '
          'or natural language.',
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'in the free tier, you can use a variety of commands to '
          'start, update, finish and rate books - i tried to make the '
          'commands as simple as possible so anyone can use the app '
          'easily. the commands are:',
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final command in _commands) _CommandLine(command),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'ps. when i say <> it means you should enter your personal '
          'items - e.g. <book> means enter the book name.',
          style: GoogleFonts.inter(fontStyle: FontStyle.italic),
        ),
      ],
    );
  }
}

/// One line of the free-tier command list — the command itself in
/// monospace (matching how it appears in [CommandWall] above), a bullet
/// to set it apart from the surrounding prose.
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
