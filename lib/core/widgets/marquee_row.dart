import 'package:flutter/material.dart';

/// A horizontally auto-scrolling row of [children], looping seamlessly.
///
/// Extracted from the onboarding tutorial's command wall so any other
/// screen — the paywall's feature tiles, for one — can get the same
/// self-scrolling ticker without re-deriving the measure-then-loop
/// trick: the child set is measured once (an invisible copy, laid out
/// but never painted), then the visible row repeats that same set
/// enough times to cover the scroll distance, and the scroll offset
/// wraps every time it has moved exactly one set's width — since the
/// content one set-width later is identical to the start, the wrap is
/// invisible.
class MarqueeRow extends StatefulWidget {
  const MarqueeRow({
    super.key,
    required this.children,
    required this.duration,
    this.reverse = false,
    this.height = 40,
    this.spacing = 8,
  });

  final List<Widget> children;
  final Duration duration;
  final bool reverse;
  final double height;
  final double spacing;

  @override
  State<MarqueeRow> createState() => _MarqueeRowState();
}

class _MarqueeRowState extends State<MarqueeRow>
    with SingleTickerProviderStateMixin {
  /// How many times the child set is repeated in the visible (scrolling)
  /// row — enough that the row never runs out of content even at the
  /// widest plausible viewport.
  static const _repeatCount = 4;

  final _measureKey = GlobalKey();
  double? _setWidth;

  late final _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

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

  Widget _set({Key? key}) {
    return Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final child in widget.children) ...[
          child,
          SizedBox(width: widget.spacing),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final setWidth = _setWidth;

    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          // Never painted — exists only so its RenderBox can be
          // measured after the first frame. Given unbounded width (via
          // OverflowBox) same as the visible row below, since the
          // ambient constraint here is only ~one screen wide and the
          // full child set is usually wider than that.
          OverflowBox(
            maxWidth: double.infinity,
            alignment: Alignment.centerLeft,
            child: Opacity(opacity: 0, child: _set(key: _measureKey)),
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
                      children: [for (var i = 0; i < _repeatCount; i++) _set()],
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
