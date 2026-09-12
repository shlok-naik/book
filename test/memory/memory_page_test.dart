import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/memory/data/memory_repository.dart';
import 'package:book/features/memory/domain/memory.dart';
import 'package:book/features/memory/domain/memory_exception.dart';
import 'package:book/features/memory/presentation/controllers/memory_controller.dart';
import 'package:book/features/memory/presentation/memory_scope.dart';
import 'package:book/features/memory/presentation/pages/memory_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The memory tab — the reader's own notes, lifted out of the old
/// profile page and given a tab of their own. What matters here is the
/// four states it can be in, and that a failed load never looks like an
/// empty one.

/// An in-memory notes store. [failure], when set, is what [fetchAll]
/// throws.
class _FakeMemoryRepository extends MemoryRepository {
  _FakeMemoryRepository({this.memories = const [], this.failure});

  final List<Memory> memories;
  final MemoryException? failure;

  final List<String> deleted = [];

  @override
  Future<List<Memory>> fetchAll() async {
    if (failure != null) throw failure!;
    return memories;
  }

  @override
  Future<void> delete(String id) async => deleted.add(id);
}

Memory _memory({required String id, String? title, required String note}) {
  return Memory(
    id: id,
    bookTitle: title,
    note: note,
    createdAt: DateTime.utc(2026, 9, 1),
  );
}

Future<void> pumpMemoryPage(
  WidgetTester tester,
  MemoryRepository repository,
) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final controller = MemoryController(repository: repository);
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MemoryScope(
      controller: controller,
      child: MaterialApp(theme: AppTheme.light, home: const MemoryPage()),
    ),
  );
  // One frame to mount, one for the post-frame `load()` kick, one for
  // the rebuild its result triggers.
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('lists every saved memory, book title and note together', (
    tester,
  ) async {
    await pumpMemoryPage(
      tester,
      _FakeMemoryRepository(
        memories: [
          _memory(id: 'm1', title: 'Dune', note: 'The ending gutted me.'),
          _memory(id: 'm2', note: 'I read better in the morning.'),
        ],
      ),
    );

    expect(find.text('memory'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('The ending gutted me.'), findsOneWidget);
    expect(find.text('I read better in the morning.'), findsOneWidget);
  });

  testWidgets('groups notes about the same book under one heading', (
    tester,
  ) async {
    await pumpMemoryPage(
      tester,
      _FakeMemoryRepository(
        memories: [
          _memory(id: 'm1', title: 'Dune', note: 'The ending gutted me.'),
          _memory(id: 'm2', title: 'Dune', note: 'Paul is not a hero.'),
        ],
      ),
    );

    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('The ending gutted me.'), findsOneWidget);
    expect(find.text('Paul is not a hero.'), findsOneWidget);
  });

  testWidgets('a note with no book groups under "general"', (tester) async {
    await pumpMemoryPage(
      tester,
      _FakeMemoryRepository(
        memories: [_memory(id: 'm1', note: 'I read better in the morning.')],
      ),
    );

    expect(find.text('general'), findsOneWidget);
  });

  testWidgets('says what an empty list means rather than showing nothing', (
    tester,
  ) async {
    await pumpMemoryPage(tester, _FakeMemoryRepository());

    expect(find.textContaining('nothing remembered yet'), findsOneWidget);
  });

  testWidgets('a failed load says so, and does not read as empty', (
    tester,
  ) async {
    await pumpMemoryPage(
      tester,
      _FakeMemoryRepository(failure: const MemoryException("You're offline.")),
    );

    expect(find.text("You're offline."), findsOneWidget);
    // The empty-state copy would tell the reader they have never saved
    // anything, which is a different — and wrong — statement.
    expect(find.textContaining('nothing remembered yet'), findsNothing);
  });

  testWidgets('forgetting a memory removes it and tells the repository', (
    tester,
  ) async {
    final repository = _FakeMemoryRepository(
      memories: [_memory(id: 'm1', title: 'Dune', note: 'The ending.')],
    );
    await pumpMemoryPage(tester, repository);

    expect(find.text('The ending.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(find.text('The ending.'), findsNothing);
    expect(repository.deleted, ['m1']);
  });

  testWidgets('each row reads as one sentence to a screen reader', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpMemoryPage(
      tester,
      _FakeMemoryRepository(
        memories: [
          _memory(id: 'm1', title: 'Dune', note: 'The ending gutted me.'),
        ],
      ),
    );

    expect(
      find.bySemanticsLabel('Dune. The ending gutted me.'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Forget this memory'), findsOneWidget);

    handle.dispose();
  });
}
