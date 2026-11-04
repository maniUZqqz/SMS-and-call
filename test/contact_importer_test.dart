import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:untitled3/features/contacts/data/contact_importer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('imports Persian contacts from UTF-8 CSV', () async {
    final directory = await Directory.systemTemp.createTemp('contact-csv-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/contacts.csv');
    await file.writeAsBytes(
      utf8.encode(
        '\uFEFFنام,شماره موبایل,توضیحات\n'
        'علی رضایی,۰۹۱۲۳۴۵۶۷۸۹,مشتری ویژه\n'
        'ردیف ناقص,,بدون شماره',
      ),
    );

    final result = await ContactImporter.parse(
      path: file.path,
      fileName: 'contacts.csv',
    );

    expect(result.contacts, hasLength(1));
    expect(result.contacts.single.name, 'علی رضایی');
    expect(result.contacts.single.phone, '09123456789');
    expect(result.contacts.single.note, 'مشتری ویژه');
    expect(result.skippedRows, 1);
  });

  test('imports contacts from a standard XLSX worksheet', () async {
    final directory = await Directory.systemTemp.createTemp('contact-xlsx-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/contacts.xlsx');
    final sharedStrings = utf8.encode(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<si><t>نام</t></si>'
      '<si><t>شماره موبایل</t></si>'
      '<si><t>توضیحات</t></si>'
      '<si><t>سارا احمدی</t></si>'
      '<si><t>09121112233</t></si>'
      '<si><t>همکار فروش</t></si>'
      '</sst>',
    );
    final worksheet = utf8.encode(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetData>'
      '<row r="1">'
      '<c r="A1" t="s"><v>0</v></c>'
      '<c r="B1" t="s"><v>1</v></c>'
      '<c r="C1" t="s"><v>2</v></c>'
      '</row>'
      '<row r="2">'
      '<c r="A2" t="s"><v>3</v></c>'
      '<c r="B2" t="s"><v>4</v></c>'
      '<c r="C2" t="s"><v>5</v></c>'
      '</row>'
      '</sheetData>'
      '</worksheet>',
    );
    await file.writeAsBytes(
      _deflatedZip({
        'xl/sharedStrings.xml': sharedStrings,
        'xl/worksheets/sheet1.xml': worksheet,
      }),
    );

    final result = await ContactImporter.parse(
      path: file.path,
      fileName: 'contacts.xlsx',
    );

    expect(result.contacts, hasLength(1));
    expect(result.contacts.single.name, 'سارا احمدی');
    expect(result.contacts.single.phone, '09121112233');
    expect(result.contacts.single.note, 'همکار فروش');
  });
}

Uint8List _deflatedZip(Map<String, List<int>> files) {
  final local = BytesBuilder(copy: false);
  final central = BytesBuilder(copy: false);
  var localOffset = 0;

  for (final entry in files.entries) {
    final name = utf8.encode(entry.key);
    final content = entry.value;
    final compressed = ZLibEncoder(raw: true).convert(content);
    local
      ..add(_u32(0x04034B50))
      ..add(_u16(20))
      ..add(_u16(0))
      ..add(_u16(8))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u32(0))
      ..add(_u32(compressed.length))
      ..add(_u32(content.length))
      ..add(_u16(name.length))
      ..add(_u16(0))
      ..add(name)
      ..add(compressed);

    central
      ..add(_u32(0x02014B50))
      ..add(_u16(20))
      ..add(_u16(20))
      ..add(_u16(0))
      ..add(_u16(8))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u32(0))
      ..add(_u32(compressed.length))
      ..add(_u32(content.length))
      ..add(_u16(name.length))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u32(0))
      ..add(_u32(localOffset))
      ..add(name);
    localOffset += 30 + name.length + compressed.length;
  }

  final localBytes = local.takeBytes();
  final centralBytes = central.takeBytes();
  final output = BytesBuilder(copy: false)
    ..add(localBytes)
    ..add(centralBytes)
    ..add(_u32(0x06054B50))
    ..add(_u16(0))
    ..add(_u16(0))
    ..add(_u16(files.length))
    ..add(_u16(files.length))
    ..add(_u32(centralBytes.length))
    ..add(_u32(localBytes.length))
    ..add(_u16(0));
  return output.takeBytes();
}

Uint8List _u16(int value) {
  return Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little);
}

Uint8List _u32(int value) {
  return Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);
}
