import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
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
    final byCategory = <CommandCategory, List<CommandReference>>{};
    for (final command in CommandCatalog.all) {
      (byCategory[command.category] ??= []).add(command);
    }

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
                      style: context.fonts.body(
                        fontSize: 13,
                        height: 1.5,
                        color: colors.secondaryText,
                      ),
                    ),
                    for (final category in CommandCategory.values)
                      if (byCategory[category] case final commands?) ...[
                        const SizedBox(height: AppSpacing.lg),
                        SettingsSection(
                          title: category.label,
                          rows: [
                            for (final command in commands)
                              _CommandRow(command),
                          ],
                        ),
                      ],
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
              style: context.fonts.interface(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              command.description,
              style: context.fonts.body(
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
                style: context.fonts.interface(
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
