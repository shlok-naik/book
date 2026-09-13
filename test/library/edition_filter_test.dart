import 'package:book/features/library/data/google_book.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/book_edition.dart';
import 'package:book/features/library/domain/edition_filter.dart';
import 'package:flutter_test/flutter_test.dart';

const _dune = Book(
  id: 'b1',
  googleBooksId: 'gb-dune',
  title: 'Dune',
  author: 'Frank Herbert',
);

GoogleBook _volume(
  String id, {
  String title = 'Dune',
  String? subtitle,
  List<String> authors = const ['Frank Herbert'],
  String? printType = 'BOOK',
  bool isEbook = false,
  String? isbn13,
  String? publishedDate,
}) => GoogleBook(
  id: id,
  title: title,
  subtitle: subtitle,
  authors: authors,
  printType: printType,
  isEbook: isEbook,
  isbn13: isbn13,
  publishedDate: publishedDate,
);

void main() {
  group('EditionFilter.formatOf', () {
    test('an ebook is whatever Google sells as one', () {
      expect(
        EditionFilter.formatOf(_volume('a', isEbook: true)),
        EditionFormat.ebook,
      );
    });

    test('a BOOK with an ISBN and no ebook sale is physical', () {
      expect(
        EditionFilter.formatOf(_volume('a', isbn13: '9780441013593')),
        EditionFormat.physical,
      );
    });

    test('magazines and format-less volumes are excluded', () {
      expect(
        EditionFilter.formatOf(
          _volume('a', printType: 'MAGAZINE', isbn13: '1'),
        ),
        isNull,
      );
      expect(EditionFilter.formatOf(_volume('a')), isNull);
    });
  });

  group('EditionFilter.editionsOf', () {
    test('keeps ebook and physical editions of the same book', () {
      final editions = EditionFilter.editionsOf(_dune, [
        _volume('e1', isEbook: true, publishedDate: '2010'),
        _volume('p1', isbn13: '978', publishedDate: '2005-08-02'),
        _volume(
          'p2',
          title: 'Dune: Deluxe Edition',
          isbn13: '979',
          publishedDate: '2019',
        ),
      ]);

      expect(editions.map((e) => e.googleBooksId), ['e1', 'p2', 'p1']);
      expect(editions.first.format, EditionFormat.ebook);
      expect(editions.every((e) => e.id == null), isTrue);
    });

    test('drops other books, study guides, audio and other authors', () {
      final editions = EditionFilter.editionsOf(_dune, [
        _volume('sequel', title: 'Dune Messiah', isbn13: '1'),
        _volume('guide', title: 'Dune', subtitle: 'A Study Guide', isbn13: '2'),
        _volume('summary', title: 'Summary of Dune', isbn13: '3'),
        _volume('audio', title: 'Dune (Unabridged Audio CD)', isbn13: '4'),
        _volume('other', authors: const ['Someone Else'], isbn13: '5'),
        _volume('mag', printType: 'MAGAZINE', isbn13: '6'),
        _volume('nothing'),
        _volume('ok', authors: const ['Herbert, Frank'], isbn13: '7'),
        _volume('initial', authors: const ['F. Herbert'], isbn13: '8'),
        // Real Google result for intitle:"Dune": same title word, same
        // surname, different Herbert.
        _volume(
          'heir',
          subtitle: 'The Heir of Caladan',
          authors: const ['Brian Herbert', 'Kevin J Anderson'],
          isbn13: '9',
        ),
        _volume('tie-in', title: 'Dune (Movie Tie-In)', isbn13: '10'),
      ]);

      expect(editions.map((e) => e.googleBooksId).toSet(), {
        'ok',
        'initial',
        'tie-in',
      });
    });

    test('de-duplicates repeated volume ids and caps the list', () {
      final editions = EditionFilter.editionsOf(_dune, [
        for (var i = 0; i < 60; i++) _volume('v${i % 50}', isbn13: '$i'),
      ]);
      expect(editions, hasLength(EditionFilter.maxEditions));
      expect(editions.map((e) => e.googleBooksId).toSet(), hasLength(40));
    });

    test('accepts a volume without authors when the title matches', () {
      final editions = EditionFilter.editionsOf(_dune, [
        _volume('a', authors: const [], isbn13: '1'),
      ]);
      expect(editions, hasLength(1));
    });

    test('a punctuation-only title matches nothing rather than everything', () {
      const odd = Book(id: 'x', googleBooksId: 'x', title: '?!', author: 'Z');
      expect(
        EditionFilter.editionsOf(odd, [_volume('a', title: '?!', isbn13: '1')]),
        isEmpty,
      );
    });

    test('handles accented titles', () {
      const book = Book(
        id: 'x',
        googleBooksId: 'x',
        title: 'Cien años de soledad',
        author: 'Gabriel García Márquez',
      );
      final editions = EditionFilter.editionsOf(book, [
        _volume(
          'a',
          title: 'Cien Años De Soledad',
          authors: const ['Gabriel García Márquez'],
          isEbook: true,
        ),
      ]);
      expect(editions, hasLength(1));
    });
  });

  test('queryFor searches the main title and the author surname', () {
    expect(
      EditionFilter.queryFor(
        const Book(
          id: 'x',
          googleBooksId: 'x',
          title: 'Dune: Deluxe Edition',
          author: 'Frank Herbert',
        ),
      ),
      'intitle:"Dune" inauthor:"Herbert"',
    );
    expect(
      EditionFilter.queryFor(
        const Book(
          id: 'x',
          googleBooksId: 'x',
          title: 'Untitled "Draft"',
          author: Book.unknownAuthor,
        ),
      ),
      'intitle:"Untitled Draft"',
    );
  });

  group('plainTextFromHtml', () {
    test('turns paragraphs and breaks into newlines and decodes entities', () {
      expect(
        plainTextFromHtml(
          '<p>Set on the desert planet <i>Arrakis</i> &amp; beyond.</p>'
          '<p>A tale of&nbsp;politics<br>and religion &#8212; epic.</p>',
        ),
        'Set on the desert planet Arrakis & beyond.\n\n'
        'A tale of politics\nand religion — epic.',
      );
    });

    test('leaves plain text alone and survives a bogus entity', () {
      expect(plainTextFromHtml('Just text.'), 'Just text.');
      expect(plainTextFromHtml('Bad &#99999999; entity'), 'Bad entity');
    });
  });
}
