/// A small RFC 4180 CSV reader and writer — enough for Goodreads exports
/// and the app's own CSV export, with no package behind it.
///
/// Reading handles quoted fields with embedded commas, line breaks and
/// doubled quotes, CRLF or LF line endings, and a leading byte-order mark.
abstract final class CsvCodec {
  static List<List<String>> decode(String input) {
    var text = input;
    if (text.startsWith('﻿')) text = text.substring(1);

    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    var fieldStarted = false;

    void endField() {
      row.add(field.toString());
      field.clear();
      fieldStarted = false;
    }

    void endRow() {
      endField();
      // A blank line is not a row of one empty field.
      if (!(row.length == 1 && row.first.isEmpty)) rows.add(row);
      row = <String>[];
    }

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (inQuotes) {
        if (char == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(char);
        }
        continue;
      }
      switch (char) {
        case '"' when !fieldStarted || field.isEmpty:
          inQuotes = true;
          fieldStarted = true;
        case ',':
          endField();
        case '\r':
          if (i + 1 < text.length && text[i + 1] == '\n') i++;
          endRow();
        case '\n':
          endRow();
        default:
          field.write(char);
          fieldStarted = true;
      }
    }
    if (field.isNotEmpty || row.isNotEmpty || fieldStarted) endRow();
    return rows;
  }

  static String encode(List<List<String>> rows) {
    final buffer = StringBuffer();
    for (final row in rows) {
      buffer.write(row.map(_escape).join(','));
      buffer.write('\r\n');
    }
    return buffer.toString();
  }

  static String _escape(String value) {
    // A leading =, +, - or @ is read as a formula by spreadsheet apps; a
    // title like "=Dune" must open as text, not execute.
    final safe = value.startsWith(RegExp(r'[=+\-@]')) && value.length > 1
        ? "'$value"
        : value;
    if (!safe.contains(RegExp('[",\r\n]'))) return safe;
    return '"${safe.replaceAll('"', '""')}"';
  }
}
