import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// The screen shown when the app cannot start at all — configuration is
/// missing, or Supabase refused to initialize.
///
/// This is deliberately a whole `MaterialApp` of its own rather than a
/// route inside the real one: at the point it is used there is no
/// initialized Supabase client, so none of the app's normal screens
/// could be built even if we wanted them. It is also the reason
/// [BookApp] never has to defend against a half-initialized world.
///
/// The wording splits on audience. A missing key is a *build*
/// misconfiguration — only ever seen by whoever built the app, so it
/// names the keys and how to supply them. Anything else is shown to a
/// reader, and says only that something went wrong and to try again.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.missingKeys});

  /// Configuration keys that resolved to nothing, or empty when the
  /// failure was something else (see the class doc).
  final List<String> missingKeys;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'cactus',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: _StartupFailureBody(missingKeys: missingKeys),
    );
  }
}

class _StartupFailureBody extends StatelessWidget {
  const _StartupFailureBody({required this.missingKeys});

  final List<String> missingKeys;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isMisconfigured = missingKeys.isNotEmpty;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMisconfigured ? 'Not configured' : "Couldn't start",
                  style: GoogleFonts.fraunces(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  isMisconfigured
                      ? 'This build is missing configuration it needs to '
                            'run.'
                      : "cactus couldn't reach its services on startup. "
                            'Check your connection and open it again.',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    height: 1.5,
                    color: colors.secondaryText,
                  ),
                ),
                // The key names and the build flag are useful only to
                // whoever produced the build, so they stay out of
                // release entirely.
                if (isMisconfigured && !kReleaseMode) ...[
                  const SizedBox(height: AppSpacing.lg),
                  for (final key in missingKeys)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: Text(
                        '--dart-define=$key=…',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 13,
                          color: colors.accent,
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Or copy .env.example to .env and fill it in.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: colors.secondaryText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
