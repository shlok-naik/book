import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A horizontally auto-scrolling row of [children], looping seamlessly
/// and endlessly.
///
/// Extracted from the onboarding tutorial's command wall so any other
/// screen — the paywall's feature tiles, for one — can get the same
/// self-scrolling ticker without re-deriving the measure-then-loop
/// trick: the child set is measured once (an invisible copy, laid out
/// but never painted), then the visible row repeats that same set
/// enough times to cover the scroll distance.
///
/// Position is driven by a raw [Ticker] rather than
/// [AnimationController.repeat] — the offset is `elapsed % duration`
/// read straight off the ticker's own monotonically-increasing clock,
/// so there's no internal simulation object restarting every lap to
/// possibly desync from. Since the content one set-width later is
/// identical to the start, the wrap the modulo produces is invisible.
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

  /// 0.0–1.0 progress through one lap, updated every frame by [_ticker].
  /// A [ValueNotifier] rather than `setState` so only the translated
  /// row rebuilds each tick, not this whole widget.
  final _progress = ValueNotifier<double>(0);

  late final Ticker _ticker = createTicker(_onTick);

  @override
  void initState() {
    super.initState();
    _ticker.start();
    WidgetsBinding.instance.addPostFrameCallback(_measure);
  }

  void _onTick(Duration elapsed) {
    final periodUs = widget.duration.inMicroseconds;
    if (periodUs <= 0) return;
    _progress.value = (elapsed.inMicroseconds % periodUs) / periodUs;
  }

  void _measure(Duration _) {
    final box = _measureKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !mounted) return;
    setState(() => _setWidth = box.size.width);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _progress.dispose();
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
            ValueListenableBuilder<double>(
              valueListenable: _progress,
              builder: (context, progress, _) {
                final dx = widget.reverse
                    ? -(1 - progress) * setWidth
                    : -progress * setWidth;
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
