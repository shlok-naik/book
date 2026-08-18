import 'package:flutter/material.dart';

import '../../data/onboarding_profile_repository.dart';
import '../../data/session_service.dart';
import '../widgets/command_wall.dart';
import 'reading_goal_page.dart';
import 'tutorial_step_page.dart';

/// Step 1 of the post-welcome sequence, shown right after the welcome
/// screen: a tilted wall of the log page's own commands, each row
/// scrolling sideways — in place of the screenshot Pushr's equivalent
/// step uses.
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
      // Placeholder — the real explanation of the log page's commands
      // (start/update/finish/rate/delete) belongs here once written.
      description: 'tutorial copy goes here.',
      onContinue: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReadingGoalPage(session: session, profiles: profiles),
        ),
      ),
    );
  }
}
