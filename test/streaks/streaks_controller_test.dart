import 'dart:async';

import 'package:book/features/library/data/reading_event_repository.dart';
import 'package:book/features/library/domain/library_exception.dart';
import 'package:book/features/library/domain/reading_event.dart';
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

/// A source that only ever fails — for the "we could not find out"
/// branch, which must not be confused with "there is nothing here".
class FailingReadingEventRepository extends ReadingEventRepository {
  FailingReadingEventRepository(this.failure);

  final Object failure;

  // `Future.error` rather than `throw`, so [failure] can be an Error as
  // well as an Exception — the controller has to cope with both, and
  // `only_throw_errors` rightly objects to throwing a bare Object.
  @override
  Future<List<ReadingEvent>> fetchForYear(int year) => Future.error(failure);
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
    test('groups events by local day, oldest first within a day', () async {
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
      expect(controller.days, [day]);
      final events = controller.eventsFor(day);
      expect(events, hasLength(2));
      expect(events.first.type, ReadingEventType.start);
      expect(events.last.type, ReadingEventType.finish);
      expect(controller.eventsFor(DateTime(2026, 3, 6)), isEmpty);
    });

    test('lists days newest first', () async {
      final controller = StreaksController(
        events: FakeReadingEventRepository([
          _event(ReadingEventType.start, DateTime.utc(2026, 1, 1), title: 'A'),
          _event(ReadingEventType.start, DateTime.utc(2026, 6, 1), title: 'B'),
          _event(ReadingEventType.start, DateTime.utc(2026, 3, 15), title: 'C'),
        ]),
      );

      await controller.load(2026);

      expect(controller.days, [
        DateTime(2026, 6, 1),
        DateTime(2026, 3, 15),
        DateTime(2026, 1, 1),
      ]);
    });

    test(
      'a day logged live re-sorts into place rather than landing at the end',
      () async {
        final controller = StreaksController(
          events: FakeReadingEventRepository([
            _event(
              ReadingEventType.start,
              DateTime.utc(2026, 1, 2),
              title: 'A',
            ),
          ]),
        );
        await controller.load(2026);

        // A fresh command lands on 11.9 — later in the same year than
        // the 1.2 already loaded — so it has to sort *before* 1.2, not
        // just get appended after it.
        controller.applyEvent(
          _event(ReadingEventType.start, DateTime.utc(2026, 11, 9), title: 'B'),
        );

        expect(controller.days, [DateTime(2026, 11, 9), DateTime(2026, 1, 2)]);
      },
    );

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
          controller.eventsFor(DateTime(2026, 6, 1)).single.type,
          ReadingEventType.start,
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

      expect(controller.eventsFor(DateTime(2027, 1, 1)), isEmpty);
    });

    test('ignores an event that arrives before anything has loaded', () {
      final controller = StreaksController(
        events: FakeReadingEventRepository([]),
      );

      controller.applyEvent(
        _event(ReadingEventType.start, DateTime.utc(2026, 6, 1), title: 'Dune'),
      );

      expect(controller.eventsFor(DateTime(2026, 6, 1)), isEmpty);
    });
  });

  group('removeTitle', () {
    test('drops every loaded event for that title', () async {
      final controller = StreaksController(
        events: FakeReadingEventRepository([
          _event(
            ReadingEventType.start,
            DateTime.utc(2026, 3, 1),
            title: 'Dune',
          ),
          _event(
            ReadingEventType.finish,
            DateTime.utc(2026, 3, 20),
            title: 'Dune',
          ),
          _event(
            ReadingEventType.start,
            DateTime.utc(2026, 3, 20),
            title: 'Neuromancer',
          ),
        ]),
      );
      await controller.load(2026);

      controller.removeTitle('Dune');

      expect(controller.eventsFor(DateTime(2026, 3, 1)), isEmpty);
      expect(
        controller.eventsFor(DateTime(2026, 3, 20)).single.title,
        'Neuromancer',
        reason: 'an unrelated title on the same day is left alone',
      );
    });

    test('drops a day entirely once its last event is removed', () async {
      final controller = StreaksController(
        events: FakeReadingEventRepository([
          _event(
            ReadingEventType.start,
            DateTime.utc(2026, 3, 1),
            title: 'Dune',
          ),
        ]),
      );
      await controller.load(2026);

      controller.removeTitle('Dune');

      expect(controller.days, isEmpty);
    });

    test('notifies listeners only when something actually changed', () async {
      final controller = StreaksController(
        events: FakeReadingEventRepository([
          _event(
            ReadingEventType.start,
            DateTime.utc(2026, 3, 1),
            title: 'Dune',
          ),
        ]),
      );
      await controller.load(2026);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.removeTitle('Neuromancer');
      expect(notifications, 0, reason: 'nothing in the loaded year matched');

      controller.removeTitle('Dune');
      expect(notifications, 1);
    });
  });

  group('a failed load', () {
    test('exposes the failure message instead of an empty year', () async {
      final controller = StreaksController(
        events: FailingReadingEventRepository(
          const NetworkException("Couldn't load your streak history."),
        ),
      );

      await controller.load(2026);

      expect(controller.errorMessage, "Couldn't load your streak history.");
      expect(controller.isLoading, isFalse);
    });

    test(
      'reports a message for an error that is not a LibraryException',
      () async {
        final controller = StreaksController(
          events: FailingReadingEventRepository(StateError('boom')),
        );

        await controller.load(2026);

        expect(controller.errorMessage, isNotNull);
      },
    );

    test('can be retried — the failed year is not marked as loaded', () async {
      final controller = StreaksController(
        events: _FailOnceThenSucceed([
          _event(
            ReadingEventType.finish,
            DateTime.utc(2026, 3, 5),
            title: 'Dune',
          ),
        ]),
      );

      await controller.load(2026);
      expect(controller.errorMessage, isNotNull);

      await controller.load(2026);
      expect(controller.errorMessage, isNull);
      expect(controller.eventsFor(DateTime(2026, 3, 5)), isNotEmpty);
    });
  });

  group('load races', () {
    test('reload supersedes a load already in flight, and its stale answer '
        'is discarded', () async {
      final events = _GatedReadingEventRepository();
      final controller = StreaksController(events: events);

      final stale = controller.load(2026);
      // The library is replaced (an import) while that load is out.
      final reload = controller.reload(2026);
      events.answer(0, [
        _event(ReadingEventType.start, DateTime.utc(2026, 1, 1), title: 'Old'),
      ]);
      events.answer(1, [
        _event(ReadingEventType.start, DateTime.utc(2026, 2, 2), title: 'New'),
      ]);
      await Future.wait([stale, reload]);

      expect(controller.isLoading, isFalse);
      expect(controller.days, [DateTime(2026, 2, 2)]);
    });

    test('a second load of the same year joins the one in flight', () async {
      final events = _GatedReadingEventRepository();
      final controller = StreaksController(events: events);

      final first = controller.load(2026);
      final second = controller.load(2026);
      events.answer(0, const []);
      await Future.wait([first, second]);

      expect(events.requests, 1);
    });

    test('a load that lands after dispose does not notify', () async {
      final events = _GatedReadingEventRepository();
      final controller = StreaksController(events: events);
      final load = controller.load(2026);
      controller.dispose();

      events.answer(0, const []);
      await expectLater(load, completes);
    });
  });
}

/// Fails the first fetch and succeeds afterwards — what a transient
/// outage looks like from the page's "try again" button.
class _FailOnceThenSucceed extends ReadingEventRepository {
  _FailOnceThenSucceed(this.rows);

  final List<ReadingEvent> rows;
  bool _failed = false;

  @override
  Future<List<ReadingEvent>> fetchForYear(int year) async {
    if (!_failed) {
      _failed = true;
      throw const NetworkException('Offline.');
    }
    return List.of(rows);
  }
}

/// Holds every fetch open until the test answers it, by request index.
class _GatedReadingEventRepository extends ReadingEventRepository {
  final _pending = <Completer<List<ReadingEvent>>>[];

  int get requests => _pending.length;

  @override
  Future<List<ReadingEvent>> fetchForYear(int year) {
    final completer = Completer<List<ReadingEvent>>();
    _pending.add(completer);
    return completer.future;
  }

  void answer(int index, List<ReadingEvent> rows) =>
      _pending[index].complete(rows);
}
