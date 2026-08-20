import 'package:flutter/material.dart';

import '../../../shell/presentation/pages/root_shell.dart';
import '../widgets/celebration_page.dart';

/// The last screen before the app itself — shown once a reader's
/// profile is ready, whether they just finished the full sign-up flow
/// or took the sign-in shortcut. By the time a reader gets here
/// they're signed in one way or another (anonymous account or an
/// existing sign-in), so this replaces the whole navigation stack with
/// [RootShell] rather than pushing, so none of the onboarding screens
/// can be popped back to.
class FinishPage extends StatelessWidget {
  const FinishPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CelebrationPage(
      icon: const Icon(Icons.check_circle, size: 72, color: Colors.green),
      title: 'All Set!',
      message:
          'welcome to cactus - your profile is now ready to use. you can '
          'now start to add your library or import it from elsewhere and '
          'most importantly: start reading.',
      buttonLabel: "let's go",
      onContinue: () => Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RootShell()),
        (route) => false,
      ),
    );
  }
}
