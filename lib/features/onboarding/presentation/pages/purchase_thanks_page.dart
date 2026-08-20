import 'package:flutter/material.dart';

import '../widgets/celebration_page.dart';

/// Shown once, right after a real purchase completes on [PaywallPage].
class PurchaseThanksPage extends StatelessWidget {
  const PurchaseThanksPage({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return CelebrationPage(
      icon: const Text('🎉', style: TextStyle(fontSize: 72)),
      title: 'Welcome!',
      message:
          "welcome to Pro - we're thrilled to have you on board. "
          "now, you don't have to worry about strict commands and "
          'can just speak while cactus handles the rest.',
      buttonLabel: 'got it',
      onContinue: onContinue,
    );
  }
}
