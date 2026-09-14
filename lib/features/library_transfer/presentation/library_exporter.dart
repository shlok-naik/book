import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/diagnostics/app_logger.dart';
import '../../library/domain/library_exception.dart';
import '../../library/presentation/controllers/library_controller.dart';
import '../domain/library_export.dart';

/// Hands a finished CSV to the platform — writes it and opens the share
/// sheet. Swapped for a fake in tests.
typedef CsvSharer = Future<void> Function(String fileName, String csv);

Future<void> _shareCsv(String fileName, String csv) async {
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}${Platform.pathSeparator}$fileName');
  await file.writeAsString(csv, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'text/csv', name: fileName)],
      subject: 'cactus library',
    ),
  );
}

/// The settings "export library" action: the whole shelf, with tags and
/// comments, as a Goodreads-compatible CSV (see [LibraryExport]).
class LibraryExporter {
  const LibraryExporter({CsvSharer? share}) : _share = share ?? _shareCsv;

  final CsvSharer _share;

  /// Returns null on success, or a message to show.
  Future<String?> export(LibraryController library, {DateTime? now}) async {
    try {
      if (library.books.isEmpty) await library.load();
      if (library.errorMessage != null && library.books.isEmpty) {
        return library.errorMessage;
      }
      if (library.books.isEmpty) return 'Your library is empty.';

      final tags = await library.notes.fetchAllTags();
      final comments = await library.notes.fetchAllComments();
      final tagsByBook = <String, List<String>>{};
      for (final tag in tags) {
        (tagsByBook[tag.userBookId] ??= []).add(tag.tag);
      }
      final commentsByBook = <String, List<String>>{};
      for (final comment in comments) {
        (commentsByBook[comment.userBookId] ??= []).add(comment.body);
      }
      final seriesNamesById = {
        for (final series in library.mySeries) series.id: series.name,
      };
      final csv = LibraryExport.build(
        library.books,
        tagsByBook: tagsByBook,
        commentsByBook: commentsByBook,
        seriesNamesById: seriesNamesById,
      );
      await _share(LibraryExport.fileName(now ?? DateTime.now()), csv);
      return null;
    } on LibraryException catch (error) {
      return error.message;
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'LibraryExporter',
        'Exporting the library failed.',
        error: error,
        stackTrace: stackTrace,
      );
      return "We couldn't export your library.";
    }
  }
}
