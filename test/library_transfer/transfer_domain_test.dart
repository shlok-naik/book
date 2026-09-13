import 'package:book/features/library/domain/book.dart';
import 'package:book/features/library/domain/library_book.dart';
import 'package:book/features/library/domain/user_book.dart';
import 'package:book/features/library_transfer/domain/csv_codec.dart';
import 'package:book/features/library_transfer/domain/goodreads_import.dart';
import 'package:book/features/library_transfer/domain/library_export.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shape of a real Goodreads "Export library" file, trimmed to a few
/// rows — quoted titles with commas, `="..."` ISBNs, a multi-line review,
/// custom shelves and an abandoned book.
const _goodreads =
    '﻿Book Id,Title,Author,Author l-f,Additional Authors,ISBN,ISBN13,'
    'My Rating,Average Rating,Publisher,Binding,Number of Pages,'
    'Year Published,Original Publication Year,Date Read,Date Added,'
    'Bookshelves,Bookshelves with positions,Exclusive Shelf,My Review,'
    'Spoiler,Private Notes,Read Count,Owned Copies\r\n'
    '234225,"Dune (Dune, #1)",Frank Herbert,"Herbert, Frank",,'
    '"=""0441172717""","=""9780441172719""",5,4.27,Ace,Paperback,604,1990,'
    '1965,2024/03/17,2023/12/01,"sci-fi, favourites",'
    '"sci-fi (#3), favourites (#1)",read,"Loved it.<br/><br/>The desert!",'
    ',,1,0\r\n'
    '44767458,Piranesi,Susanna Clarke,"Clarke, Susanna",,"=""""","=""""",0,'
    '4.23,Bloomsbury,Hardcover,272,2020,2020,,2024/01/05,to-read,'
    'to-read (#12),to-read,,,,0,0\r\n'
    '1,The Silmarillion,J.R.R. Tolkien,"Tolkien, J.R.R.",,,,0,3.9,,,,,,,'
    '2022/06/01,abandoned,abandoned (#1),abandoned,,,,0,0\r\n'
    '2,,Nobody,,,,,0,,,,,,,,,,,read,,,,0,0\r\n';

void main() {
  group('CsvCodec', () {
    test('round-trips quotes, commas and line breaks', () {
      final rows = [
        ['a', 'b, c', 'say "hi"'],
        ['line\nbreak', '', 'x'],
      ];
      expect(CsvCodec.decode(CsvCodec.encode(rows)), rows);
    });

    test('guards against spreadsheet formulas and reads them back', () {
      final encoded = CsvCodec.encode([
        ['=HYPERLINK("x")'],
      ]);
      expect(encoded, startsWith('"\'=HYPERLINK'));
    });

    test('reads LF files and ignores blank lines', () {
      expect(CsvCodec.decode('a,b\n\nc,d\n'), [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });
  });

  group('GoodreadsImport', () {
    final result = GoodreadsImport.parse(_goodreads);

    test('reads every titled row and counts the untitled one', () {
      expect(result.rows, hasLength(3));
      expect(result.skipped, 1);
    });

    test('maps a read book with its series, ISBN, rating and dates', () {
      final dune = result.rows.first;
      expect(dune.title, 'Dune');
      expect(dune.series, 'Dune');
      expect(dune.seriesPosition, 1);
      expect(dune.author, 'Frank Herbert');
      expect(dune.isbn13, '9780441172719');
      expect(dune.isbn10, '0441172717');
      expect(dune.status, ReadingStatus.finished);
      expect(dune.rating, 5);
      expect(dune.pages, 604);
      expect(dune.dateRead, DateTime(2024, 3, 17, 12));
      expect(dune.dateAdded, DateTime(2023, 12, 1, 12));
      expect(dune.tags, ['sci-fi', 'favourites']);
      expect(dune.comments, ['Loved it.\n\nThe desert!']);
      expect(dune.line, 2);
    });

    test('unrated and to-read, with empty ISBNs', () {
      final piranesi = result.rows[1];
      expect(piranesi.status, ReadingStatus.toBeRead);
      expect(piranesi.rating, isNull);
      expect(piranesi.isbn, isNull);
      expect(piranesi.tags, isEmpty);
    });

    test('an abandoned exclusive shelf is did not finish', () {
      expect(result.rows[2].status, ReadingStatus.dnf);
      expect(result.rows[2].tags, isEmpty);
    });

    test('shelf names', () {
      expect(GoodreadsImport.statusFor('did-not-finish'), ReadingStatus.dnf);
      expect(GoodreadsImport.statusFor('DNF'), ReadingStatus.dnf);
      expect(GoodreadsImport.statusFor('gave-up'), ReadingStatus.dnf);
      expect(
        GoodreadsImport.statusFor('currently-reading'),
        ReadingStatus.reading,
      );
      expect(GoodreadsImport.statusFor('wishlist'), ReadingStatus.toBeRead);
    });

    test('a file without a Title column is refused', () {
      expect(
        () => GoodreadsImport.parse('Name,Author\nx,y\n'),
        throwsA(isA<ImportFormatException>()),
      );
      expect(
        () => GoodreadsImport.parse(''),
        throwsA(isA<ImportFormatException>()),
      );
    });
  });

  group('LibraryExport', () {
    const messiah = Book(
      id: 'b2',
      googleBooksId: 'g2',
      title: 'Dune Messiah',
      author: 'Frank Herbert',
      pageCount: 250,
      isbn13: '9780593098233',
      seriesId: 's',
      seriesName: 'Dune',
      seriesPosition: 2,
    );

    final books = [
      LibraryBook(
        book: messiah,
        progress: UserBook(
          id: 'u2',
          bookId: 'b2',
          currentPage: 250,
          status: ReadingStatus.finished,
          rating: 4.5,
          startedAt: DateTime(2026, 1, 2, 9),
          finishedAt: DateTime(2026, 2, 3, 9),
        ),
      ),
      const LibraryBook(
        book: Book(
          id: 'b3',
          googleBooksId: 'g3',
          title: '=Tricky, "quoted" title',
          author: 'Someone',
        ),
        progress: UserBook(
          id: 'u3',
          bookId: 'b3',
          currentPage: 40,
          status: ReadingStatus.dnf,
        ),
      ),
    ];

    test('writes Goodreads columns plus the extras', () {
      final table = CsvCodec.decode(
        LibraryExport.build(
          books,
          tagsByBook: {
            'u2': ['sci-fi', 'book club'],
          },
          commentsByBook: {
            'u2': ['first', 'second'],
          },
        ),
      );
      expect(table.first, LibraryExport.header);
      final row = Map.fromIterables(table.first, table[1]);
      expect(row['Title'], 'Dune Messiah');
      expect(row['ISBN13'], '9780593098233');
      expect(row['My Rating'], '4.5');
      expect(row['Exclusive Shelf'], 'read');
      expect(row['Date Read'], '2026/02/03');
      expect(row['Bookshelves'], 'sci-fi, book club');
      expect(row['Series'], 'Dune');
      expect(row['Series Number'], '2');
    });

    test('an export reads back through the importer', () {
      final parsed = GoodreadsImport.parse(
        LibraryExport.build(
          books,
          tagsByBook: {
            'u2': ['sci-fi', 'book club'],
          },
          commentsByBook: {
            'u2': ['first', 'second'],
          },
        ),
      );
      final messiahRow = parsed.rows.first;
      expect(messiahRow.status, ReadingStatus.finished);
      expect(messiahRow.rating, 4.5);
      expect(messiahRow.tags, ['sci-fi', 'book club']);
      expect(messiahRow.comments, ['first', 'second']);
      expect(messiahRow.series, 'Dune');
      expect(messiahRow.seriesPosition, 2);
      expect(messiahRow.dateRead, DateTime(2026, 2, 3, 12));

      final dnf = parsed.rows[1];
      expect(dnf.title, '=Tricky, "quoted" title');
      expect(dnf.status, ReadingStatus.dnf);
      expect(dnf.currentPage, 40);
    });

    test('file name', () {
      expect(
        LibraryExport.fileName(DateTime(2026, 9, 3)),
        'cactus-library-2026-09-03.csv',
      );
    });
  });
}
