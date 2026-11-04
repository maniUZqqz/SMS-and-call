import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sms_and_call/features/contacts/data/contact_importer.dart';

import 'helpers/xlsx_builder.dart';

const _sst = '<?xml version="1.0" encoding="UTF-8"?>'
    '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">';

const _sheetOpen = '<?xml version="1.0" encoding="UTF-8"?>'
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<sheetData>';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Excel/LibreOffice خانه‌های خالیِ دارای استایل را به شکل <c r="A2" s="1"/> می‌نویسند.
  // پیش از اصلاح، این خانه خانه‌ی بعدی را می‌بلعید و ستون «نام» خالی درمی‌آمد.
  test('XLSX: an empty self-closing cell does not swallow the next cell', () async {
    final dir = await Directory.systemTemp.createTemp('xlsx-selfclose-');
    addTearDown(() => dir.delete(recursive: true));
    final file = await writeXlsx(
      dir,
      sharedStringsXml:
          '$_sst'
          '<si><t>ردیف</t></si>'
          '<si><t>نام</t></si>'
          '<si><t>شماره موبایل</t></si>'
          '<si><t>سارا احمدی</t></si>'
          '<si><t>09121112233</t></si>'
          '</sst>',
      sheetXml:
          '$_sheetOpen'
          '<row r="1">'
          '<c r="A1" t="s"><v>0</v></c>'
          '<c r="B1" t="s"><v>1</v></c>'
          '<c r="C1" t="s"><v>2</v></c>'
          '</row>'
          '<row r="2">'
          '<c r="A2" s="1"/>'
          '<c r="B2" t="s"><v>3</v></c>'
          '<c r="C2" t="s"><v>4</v></c>'
          '</row>'
          '</sheetData></worksheet>',
    );

    final result = await ContactImporter.parse(
      path: file.path,
      fileName: 'contacts.xlsx',
    );

    expect(result.contacts, hasLength(1));
    expect(result.contacts.single.name, 'سارا احمدی');
    expect(result.contacts.single.phone, '09121112233');
  });

  test('XLSX: a self-closing empty row does not swallow the next row', () async {
    final dir = await Directory.systemTemp.createTemp('xlsx-emptyrow-');
    addTearDown(() => dir.delete(recursive: true));
    final file = await writeXlsx(
      dir,
      sharedStringsXml:
          '$_sst'
          '<si><t>نام</t></si>'
          '<si><t>شماره موبایل</t></si>'
          '<si><t>علی رضایی</t></si>'
          '<si><t>09123334455</t></si>'
          '<si><t>مریم کریمی</t></si>'
          '<si><t>09125556677</t></si>'
          '</sst>',
      sheetXml:
          '$_sheetOpen'
          '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>'
          '<row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2" t="s"><v>3</v></c></row>'
          '<row r="3" ht="15"/>'
          '<row r="4"><c r="A4" t="s"><v>4</v></c><c r="B4" t="s"><v>5</v></c></row>'
          '</sheetData></worksheet>',
    );

    final result = await ContactImporter.parse(
      path: file.path,
      fileName: 'contacts.xlsx',
    );

    expect(result.contacts.map((c) => c.name), ['علی رضایی', 'مریم کریمی']);
  });

  test('XLSX: an empty shared string <si/> does not shift later strings', () async {
    final dir = await Directory.systemTemp.createTemp('xlsx-emptysi-');
    addTearDown(() => dir.delete(recursive: true));
    final file = await writeXlsx(
      dir,
      sharedStringsXml:
          '$_sst'
          '<si><t>نام</t></si>'
          '<si/>'
          '<si><t>شماره موبایل</t></si>'
          '<si><t>رضا نوری</t></si>'
          '<si><t>09127778899</t></si>'
          '</sst>',
      // اندیس‌ها: 0 نام، 1 خالی، 2 شماره موبایل، 3 رضا نوری، 4 شماره
      sheetXml:
          '$_sheetOpen'
          '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>2</v></c></row>'
          '<row r="2"><c r="A2" t="s"><v>3</v></c><c r="B2" t="s"><v>4</v></c></row>'
          '</sheetData></worksheet>',
    );

    final result = await ContactImporter.parse(
      path: file.path,
      fileName: 'contacts.xlsx',
    );

    expect(result.contacts, hasLength(1));
    expect(result.contacts.single.name, 'رضا نوری');
    expect(result.contacts.single.phone, '09127778899');
  });
}
