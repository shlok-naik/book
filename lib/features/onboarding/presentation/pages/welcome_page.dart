import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/dotted_background.dart';
import '../../../paywall/presentation/widgets/soft_pill_button.dart';
import 'add_book_tutorial_page.dart';

/// The first screen of a fresh install: "cactus" holds centered for a
/// beat, slides up a little, a short description fades in beneath it,
/// and after a further pause a "start" button appears. Tapping it moves
/// into the tutorial steps. See `BookApp` in main.dart, which builds
/// this instead of `RootShell` until `OnboardingStore` says the tutorial
/// has been seen.
///
/// It asks for nothing. The reader's account already exists by the time
/// this renders (`main` opens an anonymous session before the first
/// frame), so this whole flow is an introduction rather than a sign-up:
/// there is no name, no email, and no way to get it wrong. Linking an
/// email is offered later, in settings, to a reader who has something
/// worth backing up.
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage>
    with TickerProviderStateMixin {
  /// How long "Welcome to / cactus" sits alone, centered, before it
  /// slides up and the description starts to appear.
  static const _hold = Duration(seconds: 2);

  /// How much longer, after that reveal finishes, before the Start
  /// button fades in — Pushr's "beat" between the description landing
  /// and the action appearing, rather than everything at once.
  static const _buttonDelay = Duration(milliseconds: 900);

  /// Where the wordmark group rests once settled, as an [Alignment] y.
  static const _restingY = -0.32;
  static const _descriptionY = -0.05;

  late final _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  late final _wordmarkPosition = AlignmentTween(
    begin: Alignment.center,
    end: const Alignment(0, _restingY),
  ).animate(CurvedAnimation(parent: _reveal, curve: Curves.easeOutCubic));
  late final _descriptionOpacity = CurvedAnimation(
    parent: _reveal,
    curve: const Interval(0.5, 1, curve: Curves.easeOut),
  );

  late final _buttonController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );
  late final _buttonOpacity = CurvedAnimation(
    parent: _buttonController,
    curve: Curves.easeOut,
  );

  @override
  void initState() {
    super.initState();
    _runIntro();
  }

  Future<void> _runIntro() async {
    await Future.delayed(_hold);
    if (!mounted) return;
    await _reveal.forward();
    if (!mounted) return;
    await Future.delayed(_buttonDelay);
    if (!mounted) return;
    _buttonController.forward();
  }

  @override
  void dispose() {
    _reveal.dispose();
    _buttonController.dispose();
    super.dispose();
  }

  void _start() {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'onboarding_add_book_tutorial'),
        builder: (_) => const AddBookTutorialPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      body: DottedBackground(
        child: AnimatedBuilder(
          animation: Listenable.merge([_reveal, _buttonController]),
          builder: (context, _) {
            return Stack(
              fit: StackFit.expand,
              children: [
                Align(
                  alignment: _wordmarkPosition.value,
                  child: Text(
                    'cactus',
                    style: GoogleFonts.ebGaramond(
                      fontSize: 80,
                      fontWeight: FontWeight.w600,
                      color: colors.primaryText,
                    ),
                  ),
                ),
                Align(
                  alignment: const Alignment(0, _descriptionY),
                  child: Opacity(
                    opacity: _descriptionOpacity.value,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                      ),
                      child: Text.rich(
                        TextSpan(
                          style: GoogleFonts.inter(fontSize: 15, height: 1.5),
                          children: [
                            TextSpan(
                              text:
                                  'cactus is your next favourite reading '
                                  'companion. ',
                              style: TextStyle(
                                color: colors.primaryText,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text:
                                  'it helps you track your reading more '
                                  'efficiently than any other app in a clean '
                                  'and beautiful interface.',
                              style: TextStyle(color: colors.secondaryText),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: AppSpacing.xxl,
                  child: Opacity(
                    opacity: _buttonOpacity.value,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                      ),
                      child: SoftPillButton(
                        label: 'start',
                        backdrop: SoftPillBackdrop.background,
                        onPressed: _buttonOpacity.value == 0 ? null : _start,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
