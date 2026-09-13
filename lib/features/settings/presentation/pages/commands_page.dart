import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../logging/domain/command_catalog.dart';
import '../widgets/settings_header.dart';
import '../widgets/settings_section.dart';

/// Every text command the add tab understands, reached from settings'
/// "commands" row. Rendered straight from [CommandCatalog] — the same list
/// the parser suggests usage from — so this page can't describe a command
/// the parser doesn't have, or miss one it does.
///
/// Laid out like every other page pushed from settings: [SettingsHeader],
/// then [SettingsSection]s on the page's own gutter.
class CommandsPage extends StatelessWidget {
  const CommandsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final free = CommandCatalog.free;
    final pro = CommandCatalog.all.where((c) => c.proOnly).toList();

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SettingsHeader(title: 'commands'),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                  children: [
                    Text(
                      'type these on the add tab. <book> is a title, '
                      '[date] is optional (YYYY-MM-DD), and a book only '
                      'needs enough of its title to be found.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        height: 1.5,
                        color: colors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    SettingsSection(
                      title: 'everyone',
                      rows: [for (final command in free) _CommandRow(command)],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    SettingsSection(
                      title: 'cactus pro — written for you from a sentence',
                      rows: [for (final command in pro) _CommandRow(command)],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommandRow extends StatelessWidget {
  const _CommandRow(this.command);

  final CommandReference command;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      container: true,
      label:
          '${command.syntax}. ${command.description} '
          'For example: ${command.example}.',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              command.syntax,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              command.description,
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.5,
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                command.example,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: colors.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
