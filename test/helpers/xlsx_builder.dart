import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// یک فایل ZIP (xlsx) کوچک برای تست‌ها می‌سازد؛ فقط ورودی‌های فشرده‌ی deflate.
Uint8List buildZip(Map<String, List<int>> files) {
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

/// یک xlsx از رشته‌های اشتراکی و XML برگه می‌سازد و در [directory] می‌نویسد.
Future<File> writeXlsx(
  Directory directory, {
  required String sharedStringsXml,
  required String sheetXml,
  String name = 'contacts.xlsx',
}) async {
  final file = File('${directory.path}/$name');
  await file.writeAsBytes(
    buildZip({
      'xl/sharedStrings.xml': utf8.encode(sharedStringsXml),
      'xl/worksheets/sheet1.xml': utf8.encode(sheetXml),
    }),
  );
  return file;
}
