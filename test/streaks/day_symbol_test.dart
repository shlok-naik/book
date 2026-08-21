import 'package:book/features/library/domain/reading_event.dart';
import 'package:book/features/streaks/domain/day_symbol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('forType', () {
    test('finish is a closed circle', () {
      expect(
        DaySymbol.forType(ReadingEventType.finish),
        DaySymbol.closedCircle,
      );
    });

    test('start is a hollow circle', () {
      expect(DaySymbol.forType(ReadingEventType.start), DaySymbol.hollowCircle);
    });

    test('update, rate, and delete are all a line', () {
      for (final type in [
        ReadingEventType.update,
        ReadingEventType.rate,
        ReadingEventType.delete,
      ]) {
        expect(DaySymbol.forType(type), DaySymbol.line, reason: type.name);
      }
    });
  });

  group('strongestOf', () {
    test('null for an empty day', () {
      expect(DaySymbol.strongestOf(const []), isNull);
    });

    test('a finish overpowers a start logged the same day', () {
      expect(
        DaySymbol.strongestOf([
          ReadingEventType.start,
          ReadingEventType.finish,
        ]),
        DaySymbol.closedCircle,
      );
    });

    test('a start overpowers a line-only command', () {
      expect(
        DaySymbol.strongestOf([
          ReadingEventType.update,
          ReadingEventType.start,
        ]),
        DaySymbol.hollowCircle,
      );
    });

    test('order of the commands does not matter', () {
      expect(
        DaySymbol.strongestOf([
          ReadingEventType.finish,
          ReadingEventType.start,
        ]),
        DaySymbol.strongestOf([
          ReadingEventType.start,
          ReadingEventType.finish,
        ]),
      );
    });
  });
}
