/// How the app writes a fractional number in copy — a rating ("4.5★"), a
/// percentage ("74%"), a series number ("#2"), a CSV cell.
///
/// One decimal place at most, and never a trailing ".0": `5.0` is "5",
/// `4.5` is "4.5", `74.96` is "75". There used to be eight hand-written
/// copies of this rule, and every one called `toInt()` on its input — which
/// throws for infinity, and a long enough run of typed digits
/// (`rate dune 999…`) parses to exactly that. A non-finite value is written
/// as a symbol instead, so formatting can never be what crashes a command.
String formatCompactNumber(double value) {
  if (value.isNaN) return '?';
  if (value.isInfinite) return value.isNegative ? '-∞' : '∞';
  // Past this, rounding to a tenth would overflow; nothing real is this big.
  if (value.abs() >= 1e15) return value.toStringAsFixed(0);
  final rounded = (value * 10).round() / 10;
  return rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toStringAsFixed(1);
}

/// [value] rounded to the nearest half — half-star granularity. A value
/// that can't be rounded (NaN, infinity) comes back unchanged for the
/// caller's own range check to refuse, rather than throwing here.
double roundToHalf(double value) {
  final doubled = value * 2;
  return doubled.isFinite ? doubled.round() / 2 : value;
}

/// "12,480" — a whole count with thousands separated, since page counts
/// get long.
String formatThousands(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
