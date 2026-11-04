import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:untitled3/features/contacts/domain/contact.dart';

class ImportedContactData {
  const ImportedContactData({
    required this.name,
    required this.phone,
    required this.note,
  });

  final String name;
  final String phone;
  final String note;

  factory ImportedContactData.fromJson(Map<String, dynamic> json) {
    return ImportedContactData(
      name: (json['name'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      note: (json['note'] ?? '').toString(),
    );
  }
}

class ContactImportResult {
  const ContactImportResult({
    required this.contacts,
    required this.skippedRows,
    required this.totalRows,
  });

  final List<ImportedContactData> contacts;
  final int skippedRows;
  final int totalRows;
}

abstract final class ContactImporter {
  static Future<ContactImportResult> parse({
    required String path,
    required String fileName,
  }) async {
    final bytes = await File(path).readAsBytes();
    final raw = await compute(_parseContactFile, <String, Object>{
      'bytes': bytes,
      'fileName': fileName,
    });
    final error = (raw['error'] ?? '').toString();
    if (error.isNotEmpty) throw FormatException(error);
    final contacts = (raw['contacts'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              ImportedContactData.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
    return ContactImportResult(
      contacts: contacts,
      skippedRows: (raw['skippedRows'] as num?)?.toInt() ?? 0,
      totalRows: (raw['totalRows'] as num?)?.toInt() ?? 0,
    );
  }
}

Map<String, Object?> _parseContactFile(Map<String, Object> request) {
  try {
    final bytes = request['bytes']! as Uint8List;
    final fileName = request['fileName']!.toString().toLowerCase();
    final tables = fileName.endsWith('.xlsx')
        ? _xlsxTables(bytes)
        : <List<List<String>>>[_csvRows(bytes)];

    final contacts = <Map<String, String>>[];
    var skippedRows = 0;
    var totalRows = 0;
    var detectedColumns = false;
    for (final rows in tables) {
      final extraction = _extractContacts(rows);
      contacts.addAll(extraction.contacts);
      skippedRows += extraction.skippedRows;
      totalRows += extraction.totalRows;
      detectedColumns = detectedColumns || extraction.detectedColumns;
    }

    if (contacts.isEmpty) {
      return <String, Object?>{
        'error': detectedColumns
            ? 'ردیف معتبری پیدا نشد؛ نام و شماره موبایل هر مخاطب را بررسی کنید.'
            : 'ستون‌های نام و شماره موبایل تشخیص داده نشدند. عنوان ستون‌ها را در ردیف اول قرار دهید.',
      };
    }
    return <String, Object?>{
      'contacts': contacts,
      'skippedRows': skippedRows,
      'totalRows': totalRows,
    };
  } catch (error) {
    return <String, Object?>{
      'error': 'فایل قابل خواندن نیست یا ساختار معتبری ندارد: $error',
    };
  }
}

List<List<String>> _csvRows(Uint8List bytes) {
  final text = _decodeCsvText(bytes);
  final delimiter = _detectDelimiter(text);
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;

  for (var index = 0; index < text.length; index++) {
    final character = text[index];
    if (character == '"') {
      if (quoted && index + 1 < text.length && text[index + 1] == '"') {
        field.write('"');
        index++;
      } else {
        quoted = !quoted;
      }
      continue;
    }
    if (!quoted && character == delimiter) {
      row.add(field.toString());
      field.clear();
      continue;
    }
    if (!quoted && (character == '\n' || character == '\r')) {
      row.add(field.toString());
      field.clear();
      if (row.any((value) => value.trim().isNotEmpty)) rows.add(row);
      row = <String>[];
      if (character == '\r' &&
          index + 1 < text.length &&
          text[index + 1] == '\n') {
        index++;
      }
      continue;
    }
    field.write(character);
  }
  row.add(field.toString());
  if (row.any((value) => value.trim().isNotEmpty)) rows.add(row);
  return rows;
}

String _decodeCsvText(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decodeUtf16(bytes, littleEndian: true, offset: 2);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decodeUtf16(bytes, littleEndian: false, offset: 2);
  }
  try {
    return utf8.decode(bytes).replaceFirst('\uFEFF', '');
  } on FormatException {
    return _decodeWindows1256(bytes);
  }
}

String _decodeUtf16(
  Uint8List bytes, {
  required bool littleEndian,
  required int offset,
}) {
  final units = <int>[];
  for (var index = offset; index + 1 < bytes.length; index += 2) {
    units.add(
      littleEndian
          ? bytes[index] | (bytes[index + 1] << 8)
          : (bytes[index] << 8) | bytes[index + 1],
    );
  }
  return String.fromCharCodes(units);
}

String _decodeWindows1256(Uint8List bytes) {
  const upper = <int>[
    0x20AC,
    0x067E,
    0x201A,
    0x0192,
    0x201E,
    0x2026,
    0x2020,
    0x2021,
    0x02C6,
    0x2030,
    0x0679,
    0x2039,
    0x0152,
    0x0686,
    0x0698,
    0x0688,
    0x06AF,
    0x2018,
    0x2019,
    0x201C,
    0x201D,
    0x2022,
    0x2013,
    0x2014,
    0x06A9,
    0x2122,
    0x0691,
    0x203A,
    0x0153,
    0x200C,
    0x200D,
    0x06BA,
    0x00A0,
    0x060C,
    0x00A2,
    0x00A3,
    0x00A4,
    0x00A5,
    0x00A6,
    0x00A7,
    0x00A8,
    0x00A9,
    0x06BE,
    0x00AB,
    0x00AC,
    0x00AD,
    0x00AE,
    0x00AF,
    0x00B0,
    0x00B1,
    0x00B2,
    0x00B3,
    0x00B4,
    0x00B5,
    0x00B6,
    0x00B7,
    0x00B8,
    0x00B9,
    0x061B,
    0x00BB,
    0x00BC,
    0x00BD,
    0x00BE,
    0x061F,
    0x06C1,
    0x0621,
    0x0622,
    0x0623,
    0x0624,
    0x0625,
    0x0626,
    0x0627,
    0x0628,
    0x0629,
    0x062A,
    0x062B,
    0x062C,
    0x062D,
    0x062E,
    0x062F,
    0x0630,
    0x0631,
    0x0632,
    0x0633,
    0x0634,
    0x0635,
    0x0636,
    0x00D7,
    0x0637,
    0x0638,
    0x0639,
    0x063A,
    0x0640,
    0x0641,
    0x0642,
    0x0643,
    0x00E0,
    0x0644,
    0x00E2,
    0x0645,
    0x0646,
    0x0647,
    0x0648,
    0x00E7,
    0x00E8,
    0x00E9,
    0x00EA,
    0x00EB,
    0x0649,
    0x064A,
    0x00EE,
    0x00EF,
    0x064B,
    0x064C,
    0x064D,
    0x064E,
    0x00F4,
    0x064F,
    0x0650,
    0x00F7,
    0x0651,
    0x00F9,
    0x0652,
    0x00FB,
    0x00FC,
    0x200E,
    0x200F,
    0x06D2,
  ];
  return String.fromCharCodes(
    bytes.map((value) => value < 128 ? value : upper[value - 128]),
  );
}

String _detectDelimiter(String text) {
  final counts = <String, int>{',': 0, ';': 0, '\t': 0};
  var quoted = false;
  var lines = 0;
  for (var index = 0; index < text.length && lines < 5; index++) {
    final character = text[index];
    if (character == '"') {
      if (quoted && index + 1 < text.length && text[index + 1] == '"') {
        index++;
      } else {
        quoted = !quoted;
      }
    } else if (!quoted && counts.containsKey(character)) {
      counts[character] = counts[character]! + 1;
    } else if (!quoted && character == '\n') {
      lines++;
    }
  }
  return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}

List<List<List<String>>> _xlsxTables(Uint8List bytes) {
  final zip = _ZipReader(bytes);
  final sharedXml = zip.text('xl/sharedStrings.xml');
  final sharedStrings = sharedXml == null
      ? <String>[]
      : _parseSharedStrings(sharedXml);
  final sheetNames =
      zip.names
          .where(
            (name) => RegExp(
              r'^xl/worksheets/sheet\d+\.xml$',
              caseSensitive: false,
            ).hasMatch(name),
          )
          .toList()
        ..sort(_naturalSheetCompare);
  if (sheetNames.isEmpty) throw const FormatException('برگه‌ای در فایل نیست.');
  return sheetNames
      .map((name) => _parseWorksheet(zip.text(name)!, sharedStrings))
      .toList();
}

int _naturalSheetCompare(String first, String second) {
  int number(String value) =>
      int.tryParse(RegExp(r'(\d+)\.xml$').firstMatch(value)?.group(1) ?? '') ??
      0;
  return number(first).compareTo(number(second));
}

List<String> _parseSharedStrings(String xml) {
  final values = <String>[];
  final items = RegExp(
    r'<(?:[\w.-]+:)?si\b[^>]*>([\s\S]*?)</(?:[\w.-]+:)?si\s*>',
    caseSensitive: false,
  ).allMatches(xml);
  for (final item in items) {
    values.add(_allTagText(item.group(1)!, 't'));
  }
  return values;
}

List<List<String>> _parseWorksheet(String xml, List<String> sharedStrings) {
  final output = <List<String>>[];
  final rows = RegExp(
    r'<(?:[\w.-]+:)?row\b[^>]*>([\s\S]*?)</(?:[\w.-]+:)?row\s*>',
    caseSensitive: false,
  ).allMatches(xml);
  for (final rowMatch in rows) {
    final values = <String>[];
    var fallbackColumn = 0;
    final cells = RegExp(
      r'<(?:[\w.-]+:)?c\b([^>]*)>([\s\S]*?)</(?:[\w.-]+:)?c\s*>',
      caseSensitive: false,
    ).allMatches(rowMatch.group(1)!);
    for (final cell in cells) {
      final attributes = cell.group(1)!;
      final reference = _attribute(attributes, 'r');
      final column = reference.isEmpty
          ? fallbackColumn
          : _columnIndex(reference);
      while (values.length <= column) {
        values.add('');
      }
      values[column] = _cellText(attributes, cell.group(2)!, sharedStrings);
      fallbackColumn = column + 1;
    }
    if (values.any((value) => value.trim().isNotEmpty)) output.add(values);
  }
  return output;
}

String _cellText(String attributes, String body, List<String> sharedStrings) {
  final type = _attribute(attributes, 't');
  if (type == 'inlineStr') return _allTagText(body, 't');
  final raw = _firstTagText(body, 'v');
  if (type == 's') {
    final index = int.tryParse(raw);
    return index != null && index >= 0 && index < sharedStrings.length
        ? sharedStrings[index]
        : '';
  }
  if (type == 'str') return _decodeXml(raw);
  return _plainNumber(_decodeXml(raw));
}

String _attribute(String source, String name) {
  final doubleQuoted = RegExp(
    '\\b$name\\s*=\\s*"([^"]*)"',
    caseSensitive: false,
  ).firstMatch(source);
  if (doubleQuoted != null) return doubleQuoted.group(1) ?? '';
  return RegExp(
        "\\b$name\\s*=\\s*'([^']*)'",
        caseSensitive: false,
      ).firstMatch(source)?.group(1) ??
      '';
}

int _columnIndex(String reference) {
  var index = 0;
  for (final unit in reference.toUpperCase().codeUnits) {
    if (unit < 65 || unit > 90) break;
    index = (index * 26) + unit - 64;
  }
  return index > 0 ? index - 1 : 0;
}

String _firstTagText(String source, String tag) {
  final match = RegExp(
    '<(?:[\\w.-]+:)?$tag\\b[^>]*>([\\s\\S]*?)</(?:[\\w.-]+:)?$tag\\s*>',
    caseSensitive: false,
  ).firstMatch(source);
  return match == null ? '' : _decodeXml(match.group(1)!);
}

String _allTagText(String source, String tag) {
  final matches = RegExp(
    '<(?:[\\w.-]+:)?$tag\\b[^>]*>([\\s\\S]*?)</(?:[\\w.-]+:)?$tag\\s*>',
    caseSensitive: false,
  ).allMatches(source);
  return matches.map((match) => _decodeXml(match.group(1)!)).join();
}

String _decodeXml(String value) {
  return value
      .replaceAllMapped(
        RegExp(r'&#x([0-9a-fA-F]+);'),
        (match) => String.fromCharCode(int.parse(match.group(1)!, radix: 16)),
      )
      .replaceAllMapped(
        RegExp(r'&#(\d+);'),
        (match) => String.fromCharCode(int.parse(match.group(1)!)),
      )
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

String _plainNumber(String value) {
  final trimmed = value.trim();
  if (!RegExp(r'^[+-]?[\d.]+(?:[eE][+-]?\d+)?$').hasMatch(trimmed)) {
    return trimmed;
  }
  final number = double.tryParse(trimmed);
  if (number != null && number.isFinite && number == number.roundToDouble()) {
    return number.toStringAsFixed(0);
  }
  return trimmed;
}

class _ExtractionResult {
  const _ExtractionResult({
    required this.contacts,
    required this.skippedRows,
    required this.totalRows,
    required this.detectedColumns,
  });

  final List<Map<String, String>> contacts;
  final int skippedRows;
  final int totalRows;
  final bool detectedColumns;
}

_ExtractionResult _extractContacts(List<List<String>> sourceRows) {
  final rows = sourceRows
      .where((row) => row.any((value) => value.trim().isNotEmpty))
      .toList();
  if (rows.isEmpty) {
    return const _ExtractionResult(
      contacts: [],
      skippedRows: 0,
      totalRows: 0,
      detectedColumns: false,
    );
  }

  final columns = _detectColumns(rows);
  if (columns == null) {
    return _ExtractionResult(
      contacts: const [],
      skippedRows: rows.length,
      totalRows: rows.length,
      detectedColumns: false,
    );
  }

  final contacts = <Map<String, String>>[];
  var skipped = 0;
  final dataRows = rows.skip(columns.startRow);
  for (final row in dataRows) {
    final name = _valueAt(row, columns.name).trim();
    final phone = _normalizeImportedPhone(_valueAt(row, columns.phone));
    final note = columns.note == null
        ? ''
        : _valueAt(row, columns.note!).trim();
    if (name.isEmpty || !isValidPhoneNumber(phone)) {
      skipped++;
      continue;
    }
    contacts.add(<String, String>{'name': name, 'phone': phone, 'note': note});
  }
  return _ExtractionResult(
    contacts: contacts,
    skippedRows: skipped,
    totalRows: rows.length - columns.startRow,
    detectedColumns: true,
  );
}

class _Columns {
  const _Columns({
    required this.name,
    required this.phone,
    required this.startRow,
    this.note,
  });

  final int name;
  final int phone;
  final int? note;
  final int startRow;
}

_Columns? _detectColumns(List<List<String>> rows) {
  final headerLimit = rows.length < 12 ? rows.length : 12;
  for (var rowIndex = 0; rowIndex < headerLimit; rowIndex++) {
    final row = rows[rowIndex];
    int? name;
    int? phone;
    int? note;
    for (var column = 0; column < row.length; column++) {
      final header = _compactHeader(row[column]);
      if (_nameHeaders.contains(header)) name ??= column;
      if (_phoneHeaders.contains(header)) phone ??= column;
      if (_noteHeaders.contains(header)) note ??= column;
    }
    if (name != null && phone != null) {
      return _Columns(
        name: name,
        phone: phone,
        note: note,
        startRow: rowIndex + 1,
      );
    }
  }

  final maxColumns = rows.fold<int>(
    0,
    (current, row) => row.length > current ? row.length : current,
  );
  if (maxColumns < 2) return null;
  final sample = rows.length > 80 ? rows.take(80).toList() : rows;
  var phoneColumn = -1;
  var phoneScore = 0;
  for (var column = 0; column < maxColumns; column++) {
    final score = sample
        .where(
          (row) =>
              _looksLikeMobile(_normalizeImportedPhone(_valueAt(row, column))),
        )
        .length;
    if (score > phoneScore) {
      phoneScore = score;
      phoneColumn = column;
    }
  }
  if (phoneColumn < 0 || phoneScore == 0) return null;

  var nameColumn = -1;
  var nameScore = 0;
  for (var column = 0; column < maxColumns; column++) {
    if (column == phoneColumn) continue;
    final score = sample.where((row) {
      final value = _valueAt(row, column).trim();
      return value.isNotEmpty &&
          RegExp(r'[A-Za-z\u0600-\u06FF]').hasMatch(value);
    }).length;
    if (score > nameScore) {
      nameScore = score;
      nameColumn = column;
    }
  }
  if (nameColumn < 0 || nameScore == 0) return null;

  int? noteColumn;
  var noteScore = 0;
  for (var column = 0; column < maxColumns; column++) {
    if (column == phoneColumn || column == nameColumn) continue;
    final score = sample
        .where((row) => _valueAt(row, column).trim().isNotEmpty)
        .length;
    if (score > noteScore) {
      noteScore = score;
      noteColumn = column;
    }
  }
  return _Columns(
    name: nameColumn,
    phone: phoneColumn,
    note: noteColumn,
    startRow: 0,
  );
}

String _valueAt(List<String> row, int index) {
  return index >= 0 && index < row.length ? row[index] : '';
}

String _compactHeader(String value) {
  return normalizeContactSearch(
    value,
  ).replaceAll(RegExp(r'[\s_\-./\\()\[\]{}:،؛]+'), '');
}

final Set<String> _nameHeaders = <String>{
  'نام',
  'ناممخاطب',
  'نامکامل',
  'نامونامخانوادگی',
  'نامخانوادگی',
  'مخاطب',
  'name',
  'fullname',
  'contactname',
};

final Set<String> _phoneHeaders = <String>{
  'شماره',
  'شمارهتلفن',
  'شمارههمراه',
  'شمارهموبایل',
  'شمارهتماس',
  'تلفن',
  'تلفنهمراه',
  'موبایل',
  'همراه',
  'phone',
  'phonenumber',
  'mobile',
  'mobilenumber',
  'mobilephone',
  'mobileno',
  'contactnumber',
  'phoneno',
  'tel',
  'telephone',
};

final Set<String> _noteHeaders = <String>{
  'توضیح',
  'توضیحات',
  'یادداشت',
  'شرح',
  'note',
  'notes',
  'description',
  'comment',
};

String _normalizeImportedPhone(String value) {
  var phone = normalizePhoneNumber(_plainNumber(value));
  if (phone.length == 10 && phone.startsWith('9')) phone = '0$phone';
  if (phone.length == 12 && phone.startsWith('98')) phone = '+$phone';
  return phone;
}

bool _looksLikeMobile(String value) {
  final digits = value.startsWith('+') ? value.substring(1) : value;
  return isValidPhoneNumber(value) &&
      digits.length >= 10 &&
      (digits.startsWith('0') ||
          digits.startsWith('9') ||
          digits.startsWith('98'));
}

class _ZipEntry {
  const _ZipEntry({
    required this.method,
    required this.compressedSize,
    required this.localOffset,
  });

  final int method;
  final int compressedSize;
  final int localOffset;
}

class _ZipReader {
  _ZipReader(this.bytes) : data = ByteData.sublistView(bytes) {
    _readDirectory();
  }

  final Uint8List bytes;
  final ByteData data;
  final Map<String, _ZipEntry> _entries = <String, _ZipEntry>{};

  Iterable<String> get names => _entries.keys;

  void _readDirectory() {
    final minimum = bytes.length > 65557 ? bytes.length - 65557 : 0;
    var endOffset = -1;
    for (var index = bytes.length - 22; index >= minimum; index--) {
      if (_u32(index) == 0x06054B50) {
        endOffset = index;
        break;
      }
    }
    if (endOffset < 0) throw const FormatException('ساختار ZIP پیدا نشد.');
    final entryCount = _u16(endOffset + 10);
    var offset = _u32(endOffset + 16);
    for (var entryIndex = 0; entryIndex < entryCount; entryIndex++) {
      if (_u32(offset) != 0x02014B50) {
        throw const FormatException('فهرست فایل Excel خراب است.');
      }
      final method = _u16(offset + 10);
      final compressedSize = _u32(offset + 20);
      final nameLength = _u16(offset + 28);
      final extraLength = _u16(offset + 30);
      final commentLength = _u16(offset + 32);
      final localOffset = _u32(offset + 42);
      final nameStart = offset + 46;
      final name = utf8
          .decode(
            bytes.sublist(nameStart, nameStart + nameLength),
            allowMalformed: true,
          )
          .replaceAll('\\', '/');
      _entries[name] = _ZipEntry(
        method: method,
        compressedSize: compressedSize,
        localOffset: localOffset,
      );
      offset = nameStart + nameLength + extraLength + commentLength;
    }
  }

  String? text(String name) {
    final entry = _entries[name];
    if (entry == null) return null;
    final offset = entry.localOffset;
    if (_u32(offset) != 0x04034B50) {
      throw const FormatException('فایل داخلی Excel خراب است.');
    }
    final nameLength = _u16(offset + 26);
    final extraLength = _u16(offset + 28);
    final start = offset + 30 + nameLength + extraLength;
    final end = start + entry.compressedSize;
    if (start < 0 || end > bytes.length) {
      throw const FormatException('اندازه فایل داخلی Excel نامعتبر است.');
    }
    final compressed = bytes.sublist(start, end);
    final decoded = switch (entry.method) {
      0 => compressed,
      8 => Uint8List.fromList(ZLibDecoder(raw: true).convert(compressed)),
      _ => throw FormatException(
        'فشرده‌سازی ${entry.method} پشتیبانی نمی‌شود.',
      ),
    };
    return utf8.decode(decoded, allowMalformed: true);
  }

  int _u16(int offset) {
    if (offset < 0 || offset + 2 > bytes.length) {
      throw const FormatException('فایل ناقص است.');
    }
    return data.getUint16(offset, Endian.little);
  }

  int _u32(int offset) {
    if (offset < 0 || offset + 4 > bytes.length) {
      throw const FormatException('فایل ناقص است.');
    }
    return data.getUint32(offset, Endian.little);
  }
}
