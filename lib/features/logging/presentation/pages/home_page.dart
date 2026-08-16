import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/date_pill.dart';
import '../../domain/log_command_parser.dart';
import '../widgets/confirmation_pill.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  ParsedLogCommand? _lastResult;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _confirm(String value) {
    if (value.trim().isEmpty) return;
    setState(() => _lastResult = LogCommandParser.parse(value));
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final inputStyle = GoogleFonts.jetBrainsMono(
      fontSize: 24,
      height: 1.5,
      color: colors.primaryText,
    );

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _focusNode.requestFocus(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.xl,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: DatePill()),
                const SizedBox(height: AppSpacing.lg),
                Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      autofocus: true,
                      maxLines: null,
                      minLines: 1,
                      textInputAction: TextInputAction.done,
                      onSubmitted: _confirm,
                      style: inputStyle,
                      cursorColor: colors.accent,
                      decoration: InputDecoration(
                        hintText: 'start Dune',
                        hintStyle: inputStyle.copyWith(color: colors.secondaryText),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                if (_lastResult != null) ...[
                  ConfirmationPill(result: _lastResult!),
                  const SizedBox(height: AppSpacing.xs),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
