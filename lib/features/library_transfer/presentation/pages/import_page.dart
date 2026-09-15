import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_fonts.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/confirm_dialog.dart';
import '../../../library/presentation/library_scope.dart';
import '../../../paywall/presentation/widgets/soft_pill_button.dart';
import '../../../settings/presentation/widgets/settings_header.dart';
import '../../data/library_transfer_repository.dart';
import '../controllers/import_controller.dart';

/// Reads a picked file as text, or null when the reader cancelled.
typedef CsvPicker = Future<String?> Function();

Future<String?> _pickCsv() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['csv'],
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  return utf8.decode(bytes, allowMalformed: true);
}

Future<void> openGoodreadsImport(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'goodreads_import'),
      builder: (_) => const ImportPage(),
    ),
  );
}

/// Replaces the reader's library with a Goodreads export: pick the file,
/// watch it match, review what was found, confirm, done. See
/// [ImportController] for what each step does; this page only shows it.
class ImportPage extends StatefulWidget {
  const ImportPage({super.key, this.controller, this.pickCsv});

  /// Test seams. Null in the app.
  final ImportController? controller;
  final CsvPicker? pickCsv;

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  ImportController? _owned;

  ImportController get _controller => widget.controller ?? _owned!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.controller != null || _owned != null) return;
    final library = LibraryScope.read(context);
    _owned = ImportController(
      lookup: library.lookup,
      transfer: LibraryTransferRepository(),
      library: library,
    );
  }

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    AppHaptics.selection();
    final String? csv;
    try {
      csv = await (widget.pickCsv ?? _pickCsv)();
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'ImportPage',
        'Picking a file failed.',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) _showSnack("We couldn't open that file.");
      return;
    }
    if (csv == null || !mounted) return;
    await _controller.start(csv);
  }

  Future<void> _confirm() async {
    final library = LibraryScope.read(context);
    final count = library.books.length;
    final matched = _controller.matched.length;
    final confirmed = await showConfirmDialog(
      context,
      title: 'replace your library?',
      message: count == 0
          ? 'this adds $matched ${matched == 1 ? 'book' : 'books'} from the '
                'file.'
          : 'your $count ${count == 1 ? 'book' : 'books'}, with their tags, '
                'comments and reading history, will be deleted and replaced '
                "by the $matched from the file. this can't be undone.",
      confirmLabel: 'replace',
      routeName: 'confirm_import',
    );
    if (!confirmed || !mounted) return;
    await _controller.confirm();
    if (!mounted) return;
    if (_controller.stage == ImportStage.done) {
      AppHaptics.accepted();
    } else {
      AppHaptics.rejected();
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

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
              const SettingsHeader(title: 'import from goodreads'),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) =>
                      Semantics(liveRegion: true, child: _stage(context)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stage(BuildContext context) {
    final controller = _controller;
    return switch (controller.stage) {
      ImportStage.idle => _Intro(onChoose: _choose),
      ImportStage.matching => _Progress(
        title: 'finding your books…',
        detail: '${controller.processed} of ${controller.total}',
        fraction: controller.total == 0
            ? null
            : controller.processed / controller.total,
        onCancel: controller.cancel,
      ),
      ImportStage.review => _Review(
        controller: controller,
        onConfirm: _confirm,
      ),
      ImportStage.importing => const _Progress(
        title: 'replacing your library…',
        detail: "this can take a moment. don't close the app.",
      ),
      ImportStage.done => _Finished(
        title:
            'imported ${controller.imported} '
            '${controller.imported == 1 ? 'book' : 'books'}',
        message: 'your library and stats now come from the file.',
        actionLabel: 'done',
        onAction: () => Navigator.of(context).pop(),
      ),
      ImportStage.failed => _Finished(
        title: 'that didn’t work',
        message: controller.errorMessage ?? 'Something went wrong.',
        actionLabel: 'choose another file',
        onAction: controller.reset,
      ),
    };
  }
}

TextStyle _body(BuildContext context, AppColors colors) =>
    context.fonts.body(fontSize: 14, height: 1.5, color: colors.secondaryText);

TextStyle _title(BuildContext context, AppColors colors) =>
    context.fonts.interface(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: colors.primaryText,
    );

class _Intro extends StatelessWidget {
  const _Intro({required this.onChoose});

  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListView(
      children: [
        Text('bring your goodreads library', style: _title(context, colors)),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'on goodreads, open my books → import and export → export library, '
          'then choose the csv file it gives you.',
          style: _body(context, colors),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'read, currently reading and to-read land on the matching shelves; '
          'a shelf like "dnf" or "abandoned" becomes did not finish. ratings, '
          'dates, reviews and your other shelves (as tags) come along.',
          style: _body(context, colors),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: colors.accent.withValues(alpha: 0.5)),
          ),
          child: Text(
            'importing replaces your whole library. nothing changes until you '
            "confirm, after you've seen what was found.",
            style: _body(context, colors).copyWith(color: colors.primaryText),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SoftPillButton(label: 'choose file', onPressed: onChoose),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({
    required this.title,
    required this.detail,
    this.fraction,
    this.onCancel,
  });

  final String title;
  final String detail;
  final double? fraction;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: _title(context, colors)),
        const SizedBox(height: AppSpacing.sm),
        Text(detail, style: _body(context, colors)),
        const SizedBox(height: AppSpacing.lg),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            color: colors.accent,
            backgroundColor: colors.divider,
          ),
        ),
        if (onCancel != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onCancel,
              child: Text(
                'cancel',
                style: context.fonts.interface(
                  fontSize: 14,
                  color: colors.secondaryText,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Review extends StatelessWidget {
  const _Review({required this.controller, required this.onConfirm});

  final ImportController controller;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final matched = controller.matched.length;
    final unmatched = controller.unmatched;
    final library = LibraryScope.of(context);
    final current = library.books.length;

    return ListView(
      children: [
        Text(
          'found $matched of ${controller.total} '
          '${controller.total == 1 ? 'book' : 'books'}',
          style: _title(context, colors),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (controller.duplicates > 0)
          Text(
            '${controller.duplicates} repeated '
            '${controller.duplicates == 1 ? 'row was' : 'rows were'} merged.',
            style: _body(context, colors),
          ),
        if (controller.skipped > 0)
          Text(
            '${controller.skipped} '
            '${controller.skipped == 1 ? 'row had' : 'rows had'} no title.',
            style: _body(context, colors),
          ),
        if (unmatched.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            "couldn't find ${unmatched.length} — they won't be imported:",
            style: _body(context, colors).copyWith(color: colors.primaryText),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final item in unmatched.take(50))
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '· ${item.row.title}'
                '${item.row.author.isEmpty ? '' : ' — ${item.row.author}'}',
                style: context.fonts.interface(
                  fontSize: 12,
                  color: colors.secondaryText,
                ),
              ),
            ),
          if (unmatched.length > 50)
            Text(
              '· and ${unmatched.length - 50} more',
              style: _body(context, colors),
            ),
        ],
        const SizedBox(height: AppSpacing.lg),
        if (current > 0)
          Text(
            'replacing deletes your $current current '
            '${current == 1 ? 'book' : 'books'} and their tags, comments and '
            'reading history. your memories and reading goal stay.',
            style: _body(context, colors),
          ),
        const SizedBox(height: AppSpacing.lg),
        SoftPillButton(
          label: matched == 0 ? 'nothing to import' : 'replace my library',
          onPressed: matched == 0 ? null : onConfirm,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: controller.reset,
          child: Text(
            'choose a different file',
            style: context.fonts.interface(
              fontSize: 13,
              color: colors.secondaryText,
            ),
          ),
        ),
      ],
    );
  }
}

class _Finished extends StatelessWidget {
  const _Finished({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: _title(context, colors)),
        const SizedBox(height: AppSpacing.sm),
        Text(message, style: _body(context, colors)),
        const SizedBox(height: AppSpacing.lg),
        SoftPillButton(label: actionLabel, onPressed: onAction),
      ],
    );
  }
}
