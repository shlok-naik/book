import 'package:book/core/feedback/app_haptics.dart';
import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/library_book.dart';
import 'package:book/features/library/domain/user_book.dart';
import 'package:book/features/library/presentation/widgets/book_tile.dart';
import 'package:book/features/shell/presentation/widgets/bottom_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app is icon-heavy and text-light by design, which is exactly the
/// combination that renders an interface unusable with a screen reader
/// unless the labels are deliberate. These pin the labels down, because
/// nothing about a build failing would otherwise tell you they had been
/// dropped.

const _dune = Book(
  id: 'book-1',
  googleBooksId: 'gb-dune',
  title: 'Dune',
  author: 'Frank Herbert',
  pageCount: 300,
);

LibraryBook _entry({int page = 0, bool finished = false, double? rating}) {
  return LibraryBook(
    book: _dune,
    progress: UserBook(
      id: 'progress-1',
      bookId: _dune.id,
      currentPage: page,
      status: finished ? ReadingStatus.finished : ReadingStatus.reading,
      rating: rating,
    ),
  );
}

Widget _harness(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: child),
);

void main() {
  group('the tab bar', () {
    testWidgets('names every tab, and marks the current one selected', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _harness(BottomSwitcher(index: 2, onChanged: (_) {})),
      );

      // Icon-only slots: without these the whole primary navigation is
      // four unlabelled buttons.
      expect(find.bySemanticsLabel('Profile'), findsOneWidget);
      expect(find.bySemanticsLabel('Streak'), findsOneWidget);
      expect(find.bySemanticsLabel('Library'), findsOneWidget);
      expect(find.bySemanticsLabel('Log reading'), findsOneWidget);

      // `isSemantics` rather than `matchesSemantics`: we care that the
      // tab announces itself as a selected button, not that every other
      // flag on the node is exactly what today's framework emits.
      expect(
        tester.getSemantics(find.bySemanticsLabel('Library')),
        isSemantics(label: 'Library', isButton: true, isSelected: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Profile')),
        isSemantics(label: 'Profile', isButton: true, isSelected: false),
      );

      handle.dispose();
    });
  });

  group('a book tile', () {
    testWidgets('reads as one sentence rather than six fragments', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _harness(
          BookTile(entry: _entry(page: 150), cover: const SizedBox.shrink()),
        ),
      );

      expect(
        find.bySemanticsLabel(
          'Dune by Frank Herbert. Page 150 of 300, 50 percent.',
        ),
        findsOneWidget,
      );

      handle.dispose();
    });

    testWidgets('says "not started" rather than page zero', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _harness(BookTile(entry: _entry(), cover: const SizedBox.shrink())),
      );

      expect(
        find.bySemanticsLabel('Dune by Frank Herbert. Not started.'),
        findsOneWidget,
      );

      handle.dispose();
    });

    testWidgets('speaks a whole-number rating without a decimal point', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        _harness(
          BookTile(
            entry: _entry(page: 300, finished: true, rating: 4),
            cover: const SizedBox.shrink(),
          ),
        ),
      );

      expect(
        find.bySemanticsLabel(
          'Dune by Frank Herbert. Finished. Rated 4 out of 5.',
        ),
        findsOneWidget,
      );

      handle.dispose();
    });
  });

  group('haptics', () {
    late List<String> fired;

    setUp(() {
      fired = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              fired.add(call.arguments as String? ?? 'default');
            }
            return null;
          });
      AppHaptics.enabled = true;
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('a tab change fires exactly one selection tick', (
      tester,
    ) async {
      var index = 0;
      await tester.pumpWidget(
        _harness(
          StatefulBuilder(
            builder: (context, setState) => BottomSwitcher(
              index: index,
              onChanged: (i) => setState(() => index = i),
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.menu_book_outlined));
      await tester.pump();

      expect(fired, ['HapticFeedbackType.selectionClick']);
      expect(index, 2);
    });

    testWidgets('tapping the tab you are already on fires nothing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(BottomSwitcher(index: 2, onChanged: (_) {})),
      );

      await tester.tap(find.byIcon(Icons.menu_book_outlined));
      await tester.pump();

      // A haptic has to mean "you moved" every single time, or it stops
      // meaning anything.
      expect(fired, isEmpty);
    });

    testWidgets('nothing fires when haptics are switched off', (tester) async {
      AppHaptics.enabled = false;
      addTearDown(() => AppHaptics.enabled = true);

      var index = 0;
      await tester.pumpWidget(
        _harness(
          StatefulBuilder(
            builder: (context, setState) => BottomSwitcher(
              index: index,
              onChanged: (i) => setState(() => index = i),
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.menu_book_outlined));
      await tester.pump();

      expect(fired, isEmpty);
    });
  });
}
