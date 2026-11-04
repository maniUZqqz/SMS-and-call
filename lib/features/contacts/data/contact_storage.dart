import 'dart:convert';
import 'dart:io';

import 'package:untitled3/core/storage/app_storage.dart';
import 'package:untitled3/features/contacts/domain/contact.dart';

class ContactStorage {
  static Future<File> _file() async {
    return File('${await AppDir.path()}/sms_gateway_contacts.json');
  }

  static Future<List<Contact>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final raw = jsonDecode(content);
      if (raw is! List) return [];
      return raw
          .whereType<Map>()
          .map((item) => Contact.fromJson(Map<String, dynamic>.from(item)))
          .where((contact) => contact.id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<Contact> contacts) async {
    final file = await _file();
    await writeAtomicFile(
      file,
      jsonEncode(contacts.map((contact) => contact.toJson()).toList()),
    );
  }
}
