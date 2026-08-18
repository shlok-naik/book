import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';

/// A tilted wall of the app's commands, each row auto-scrolling
/// sideways at its own speed and direction — the "add-a-book" tutorial
/// step's demonstration of what the log page's command line looks like,
/// in place of the screenshot Pushr's equivalent step uses.
///
/// The whole stack is rotated a few degrees so each row reads as sitting
/// diagonally below the one above it, rather than a flat, static list.
class CommandWall extends StatelessWidget {
  const CommandWall({super.key});

  static const _rows = [
    [
      'start The Shining',
      'start Dune',
      'start Circe',
      'start 1984',
      'start Emma',
      'start The Hobbit',
    ],
    [
      'update Dune 120',
      'update Emma 40',
      'update 1984 210',
      'update Circe 88',
      'update The Hobbit 150',
    ],
    [
      'finish The Shining',
      'rate Dune 4.5',
      'delete Emma',
      'rate Circe 5',
      'finish 1984',
    ],
  ];

  static const _durations = [
    Duration(seconds: 18),
    Duration(seconds: 14),
    Duration(seconds: 20),
  ];

  static const _reversed = [false, true, false];

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -6 * pi / 180,
      child: ClipRect(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _rows.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              _MarqueeRow(
                commands: _rows[i],
                duration: _durations[i],
                reverse: _reversed[i],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One horizontally auto-scrolling row of [_CommandChip]s.
///
/// Loops seamlessly: the chips are measured once (an invisible copy,
/// laid out but never painted), then the visible row repeats that same
/// set enough times to cover the scroll distance, and the scroll offset
/// wraps every time it has moved exactly one set's width — since the
/// content one set-width later is identical to the start, the wrap is
/// invisible.
class _MarqueeRow extends StatefulWidget {
  const _MarqueeRow({
    required this.commands,
    required this.duration,
    required this.reverse,
  });

  final List<String> commands;
  final Duration duration;
  final bool reverse;

  @override
  State<_MarqueeRow> createState() => _MarqueeRowState();
}

class _MarqueeRowState extends State<_MarqueeRow>
    with SingleTickerProviderStateMixin {
  static const _rowHeight = 40.0;

  /// How many times the chip set is repeated in the visible (scrolling)
  /// row — enough that the row never runs out of content even at the
  /// widest plausible viewport.
  static const _repeatCount = 4;

  final _measureKey = GlobalKey();
  double? _setWidth;

  late final _controller = AnimationController(vsync: this, duration: widget.duration);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_measure);
  }

  void _measure(Duration _) {
    final box = _measureKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !mounted) return;
    setState(() => _setWidth = box.size.width);
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _chips({Key? key}) {
    return Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final command in widget.commands) ...[
          _CommandChip(command),
          const SizedBox(width: AppSpacing.sm),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final setWidth = _setWidth;

    return SizedBox(
      height: _rowHeight,
      child: Stack(
        children: [
          // Never painted — exists only so its RenderBox can be
          // measured after the first frame. Given unbounded width (via
          // OverflowBox) same as the visible row below, since the
          // ambient constraint here is only ~one screen wide and the
          // full chip set is usually wider than that.
          OverflowBox(
            maxWidth: double.infinity,
            alignment: Alignment.centerLeft,
            child: Opacity(opacity: 0, child: _chips(key: _measureKey)),
          ),
          if (setWidth != null)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final dx = widget.reverse
                    ? -(1 - _controller.value) * setWidth
                    : -_controller.value * setWidth;
                return OverflowBox(
                  maxWidth: double.infinity,
                  alignment: Alignment.centerLeft,
                  child: Transform.translate(
                    offset: Offset(dx, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [for (var i = 0; i < _repeatCount; i++) _chips()],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _CommandChip extends StatelessWidget {
  const _CommandChip(this.command);

  final String command;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        command,
        style: GoogleFonts.jetBrainsMono(fontSize: 14, color: colors.primaryText),
      ),
    );
  }
}
