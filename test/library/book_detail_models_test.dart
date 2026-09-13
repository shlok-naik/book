import 'package:book/features/library/data/book_notes_repository.dart';
import 'package:book/features/library/data/google_book.dart';
import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/book_edition.dart';
import 'package:book/features/library/domain/book_note.dart';
import 'package:book/features/library/domain/library_exception.dart';
import 'package:book/features/library/domain/user_book.dart';
import 'package:flutter_test/flutter_test.dart';

/// Row and payload parsing for everything the detail page caches or
/// stores — defensive by convention: optional fields degrade to null, and
/// only a row missing its identity is refused.
void main() {
  group('Book.fromRow extended info', () {
    test('parses every detail column, including numeric strings', () {
      final book = Book.fromRow({
        'id': 'b1',
        'google_books_id': 'g1',
        'title': 'Dune',
        'author': 'Frank Herbert',
        'subtitle': ' Deluxe ',
        'publisher': 'Ace',
        'published_date': '2005-08',
        'categories': ['Fiction', '', 42, 'Sci-Fi'],
        'language': 'en',
        'isbn_10': '0441013597',
        'isbn_13': '9780441013593',
        'average_rating': '4.3',
        'ratings_count': 1200,
        'details_fetched_at': '2026-09-13T10:00:00Z',
        'editions_fetched_at': null,
      });
      expect(book.subtitle, 'Deluxe');
      expect(book.categories, ['Fiction', 'Sci-Fi']);
      expect(book.averageRating, 4.3);
      expect(book.ratingsCount, 1200);
      expect(book.hasCachedDetails, isTrue);
      expect(book.hasCachedEditions, isFalse);
    });

    test('a row from before the migration has no cached details', () {
      final book = Book.fromRow({'id': 'b1', 'title': 'Dune'});
      expect(book.hasCachedDetails, isFalse);
      expect(book.categories, isEmpty);
    });
  });

  group('UserBook.fromRow', () {
    test('parses owned edition and shelf position', () {
      final progress = UserBook.fromRow({
        'id': 'u1',
        'book_id': 'b1',
        'status': 'dnf',
        'owned_edition_id': 'e1',
        'shelf_position': 2,
      });
      expect(progress.ownedEditionId, 'e1');
      expect(progress.shelfPosition, 2.0);
    });

    test('copyWith can clear the nullable fields', () {
      const progress = UserBook(
        id: 'u1',
        bookId: 'b1',
        currentPage: 1,
        status: ReadingStatus.reading,
        ownedEditionId: 'e1',
        shelfPosition: 1,
      );
      final cleared = progress.copyWith(
        clearOwnedEdition: true,
        clearShelfPosition: true,
      );
      expect(cleared.ownedEditionId, isNull);
      expect(cleared.shelfPosition, isNull);
    });
  });

  group('BookEdition', () {
    test('parses a row and round-trips the RPC payload', () {
      final edition = BookEdition.fromRow({
        'id': 'e1',
        'google_books_id': 'g1',
        'title': 'Dune',
        'author': 'Frank Herbert',
        'format': 'physical',
        'published_date': '2005-08-02',
        'page_count': 604,
        'isbn_13': '9780441013593',
      })!;
      expect(edition.format, EditionFormat.physical);
      expect(edition.year, '2005');
      expect(edition.toRpcJson()['format'], 'physical');
      expect(edition.toRpcJson()['page_count'], 604);
    });

    test('refuses a row with an unknown format or no id', () {
      expect(
        BookEdition.fromRow({
          'id': 'e1',
          'google_books_id': 'g1',
          'title': 'Dune',
          'format': 'audiobook',
        }),
        isNull,
      );
      expect(
        BookEdition.fromRow({
          'google_books_id': 'g1',
          'title': 'Dune',
          'format': 'ebook',
        }),
        isNull,
      );
    });

    test('year is null for a missing or malformed date', () {
      const base = BookEdition(
        googleBooksId: 'g',
        title: 't',
        author: 'a',
        format: EditionFormat.ebook,
      );
      expect(base.year, isNull);
      expect(
        const BookEdition(
          googleBooksId: 'g',
          title: 't',
          author: 'a',
          format: EditionFormat.ebook,
          publishedDate: 'c. 1965',
        ).year,
        isNull,
      );
    });
  });

  group('GoogleBook.fromJson extended fields', () {
    test('reads identifiers, sale info and ratings', () {
      final volume = GoogleBook.fromJson({
        'id': 'g1',
        'volumeInfo': {
          'title': 'Dune',
          'subtitle': 'Deluxe Edition',
          'authors': ['Frank Herbert'],
          'publisher': 'Ace',
          'publishedDate': '2019-10-01',
          'industryIdentifiers': [
            {'type': 'ISBN_10', 'identifier': '0593099311'},
            {'type': 'ISBN_13', 'identifier': '9780593099315'},
            {'type': 'OTHER', 'identifier': 'x'},
            'garbage',
          ],
          'categories': ['Fiction'],
          'averageRating': 4,
          'ratingsCount': 10,
          'printType': 'BOOK',
          'previewLink': 'http://books.google.com/x',
        },
        'saleInfo': {'isEbook': true},
      });
      expect(volume.isbn10, '0593099311');
      expect(volume.isbn13, '9780593099315');
      expect(volume.isEbook, isTrue);
      expect(volume.averageRating, 4.0);
      expect(volume.previewLink, 'https://books.google.com/x');
    });
  });

  group('tag and comment rows and validation', () {
    test('BookTag and BookComment parse and refuse bad rows', () {
      expect(
        BookTag.fromRow({
          'id': 't',
          'user_book_id': 'u',
          'tag': 'sci-fi',
          'created_at': '2026-09-13T10:00:00Z',
        })?.tag,
        'sci-fi',
      );
      expect(BookTag.fromRow({'id': 't'}), isNull);

      final comment = BookComment.fromRow({
        'id': 'c',
        'user_book_id': 'u',
        'body': 'hi',
        'created_at': '2026-09-13T10:00:00Z',
        'updated_at': '2026-09-13T10:05:00Z',
      })!;
      expect(comment.isEdited, isTrue);
      expect(BookComment.fromRow({'id': 'c', 'body': 'hi'}), isNull);
    });

    test('validateTag trims, collapses spaces, and enforces length', () {
      expect(
        BookNotesRepository.validateTag('  space   opera '),
        'space opera',
      );
      expect(
        () => BookNotesRepository.validateTag('   '),
        throwsA(isA<InvalidInputException>()),
      );
      expect(
        () => BookNotesRepository.validateTag('x' * 41),
        throwsA(isA<InvalidInputException>()),
      );
    });

    test('validateComment trims and enforces length', () {
      expect(BookNotesRepository.validateComment(' ok '), 'ok');
      expect(
        () => BookNotesRepository.validateComment(''),
        throwsA(isA<InvalidInputException>()),
      );
      expect(
        () => BookNotesRepository.validateComment('x' * 1001),
        throwsA(isA<InvalidInputException>()),
      );
    });

    test('tags compare ignoring case and surrounding space', () {
      expect(BookTag.normalize(' Sci-Fi '), BookTag.normalize('sci-fi'));
    });
  });
}
