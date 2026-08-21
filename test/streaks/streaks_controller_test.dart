import 'package:book/features/library/data/reading_event_repository.dart';
import 'package:book/features/library/domain/reading_event.dart';
import 'package:book/features/streaks/domain/day_symbol.dart';
import 'package:book/features/streaks/presentation/controllers/streaks_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory `reading_events` source — returns whatever [rows] holds for
/// any year, so tests control exactly what a load sees without touching
/// Supabase.
class FakeReadingEventRepository extends ReadingEventRepository {
  FakeReadingEventRepository(this.rows);

  final List<ReadingEvent> rows;

  @override
  Future<List<ReadingEvent>> fetchForYear(int year) async => List.of(rows);
}

ReadingEvent _event(
  ReadingEventType type,
  DateTime occurredAt, {
  String? title,
}) {
  return ReadingEvent(type: type, occurredAt: occurredAt, title: title);
}

void main() {
  group('load', () {
    test('groups events by local day and exposes a symbol per day', () async {
      final controller = StreaksController(
        events: FakeReadingEventRepository([
          _event(
            ReadingEventType.start,
            DateTime.utc(2026, 3, 5, 10),
            title: 'Dune',
          ),
          _event(
            ReadingEventType.finish,
            DateTime.utc(2026, 3, 5, 20),
            title: 'Dune',
          ),
        ]),
      );

      await controller.load(2026);

      final day = DateTime(2026, 3, 5);
      expect(controller.symbolFor(day), DaySymbol.closedCircle);
      expect(controller.eventsFor(day), hasLength(2));
      expect(controller.symbolFor(DateTime(2026, 3, 6)), isNull);
    });

    test('a second call for the same year is a no-op', () async {
      final repository = FakeReadingEventRepository([
        _event(ReadingEventType.start, DateTime.utc(2026, 1, 1), title: 'Dune'),
      ]);
      final controller = StreaksController(events: repository);

      await controller.load(2026);
      repository.rows.add(
        _event(
          ReadingEventType.finish,
          DateTime.utc(2026, 1, 2),
          title: 'Dune',
        ),
      );
      await controller.load(2026);

      expect(
        controller.eventsFor(DateTime(2026, 1, 2)),
        isEmpty,
        reason: 'the second load must not have re-fetched',
      );
    });
  });

  group('applyEvent', () {
    test(
      'folds a new event into the already-loaded year without a refetch',
      () async {
        final controller = StreaksController(
          events: FakeReadingEventRepository([]),
        );
        await controller.load(2026);

        controller.applyEvent(
          _event(
            ReadingEventType.start,
            DateTime.utc(2026, 6, 1),
            title: 'Dune',
          ),
        );

        expect(
          controller.symbolFor(DateTime(2026, 6, 1)),
          DaySymbol.hollowCircle,
        );
      },
    );

    test('notifies listeners', () async {
      final controller = StreaksController(
        events: FakeReadingEventRepository([]),
      );
      await controller.load(2026);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.applyEvent(
        _event(ReadingEventType.start, DateTime.utc(2026, 6, 1), title: 'Dune'),
      );

      expect(notifications, 1);
    });

    test('ignores an event outside the loaded year', () async {
      final controller = StreaksController(
        events: FakeReadingEventRepository([]),
      );
      await controller.load(2026);

      controller.applyEvent(
        _event(ReadingEventType.start, DateTime.utc(2027, 1, 1), title: 'Dune'),
      );

      expect(controller.symbolFor(DateTime(2027, 1, 1)), isNull);
    });

    test('ignores an event that arrives before anything has loaded', () {
      final controller = StreaksController(
        events: FakeReadingEventRepository([]),
      );

      controller.applyEvent(
        _event(ReadingEventType.start, DateTime.utc(2026, 6, 1), title: 'Dune'),
      );

      expect(controller.symbolFor(DateTime(2026, 6, 1)), isNull);
    });
  });
}
