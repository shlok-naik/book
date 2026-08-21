import 'package:flutter/material.dart';

import '../../domain/day_symbol.dart';

/// Renders one [DaySymbol] as its shape — a line for update/rate/delete,
/// a hollow ring for start, a filled circle for finish — shared by the
/// month grid's dots and the day-detail sheet's event rows so the two
/// only ever draw a symbol one way.
///
/// A null [symbol] (nothing logged that day) draws a dim open circle —
/// only the month grid passes null; the sheet's rows always have a real
/// event.
class DaySymbolMark extends StatelessWidget {
  const DaySymbolMark({
    super.key,
    required this.symbol,
    required this.diameter,
    required this.color,
    this.lineThickness = 1.2,
  });

  final DaySymbol? symbol;
  final double diameter;
  final Color color;

  /// Thickness of the [DaySymbol.line] shape — the grid and the sheet
  /// draw it at different weights for their different dot sizes.
  final double lineThickness;

  @override
  Widget build(BuildContext context) {
    switch (symbol) {
      case null:
        return Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.transparent,
            border: Border.all(
              color: color.withValues(alpha: 0.35),
              width: 1.1,
            ),
          ),
        );
      case DaySymbol.line:
        return SizedBox(
          width: diameter,
          height: lineThickness,
          child: ColoredBox(color: color),
        );
      case DaySymbol.hollowCircle:
        return Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.transparent,
            border: Border.all(color: color, width: 1.3),
          ),
        );
      case DaySymbol.closedCircle:
        return Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        );
    }
  }
}
