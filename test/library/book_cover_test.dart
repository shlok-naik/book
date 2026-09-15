import 'package:book/core/theme/app_theme.dart';
import 'package:book/features/library/presentation/widgets/book_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CoverImage.candidates', () {
    test('the cached cover first, then Open Library by ISBN', () {
      expect(
        CoverImage.candidates(
          'https://books.google.com/a.jpg',
          '978-0441172719',
        ),
        [
          'https://books.google.com/a.jpg',
          'https://covers.openlibrary.org/b/isbn/9780441172719-M.jpg?default=false',
        ],
      );
    });

    test('with no cached cover, straight to Open Library', () {
      expect(CoverImage.candidates(null, '0441172717'), [
        'https://covers.openlibrary.org/b/isbn/0441172717-M.jpg?default=false',
      ]);
    });

    test('nothing to try without a cover or a usable ISBN', () {
      expect(CoverImage.candidates('', null), isEmpty);
      expect(CoverImage.candidates(null, '12345'), isEmpty);
    });
  });

  // Every HTTP request in a widget test fails, which is exactly the case to
  // prove: each source is tried and the placeholder is what's left.
  testWidgets('falls through every source to the typographic placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Center(
          child: SizedBox(
            width: 120,
            child: BookCover(
              title: 'Dune',
              author: 'Frank Herbert',
              coverUrl: 'https://books.google.com/dune.jpg',
              isbn: '9780441172719',
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Frank Herbert'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
