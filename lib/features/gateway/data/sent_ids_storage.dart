import 'dart:convert';
import 'dart:io';

import 'package:sms_and_call/core/storage/app_storage.dart';

/// شناسه‌ی کدهایی که پیامکشان رفته است. روی دیسک می‌ماند تا با ری‌استارت سرویس،
/// تا وقتی سرور هنوز آن آیتم را در صف دارد، پیامک تکراری نرود.
class SentIdsStorage {
  static Future<File> _file() async =>
      File('${await AppDir.path()}/sms_gateway_sent_ids.json');

  static Future<Set<String>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return <String>{};
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return <String>{};
      // ترتیب درج حفظ می‌شود (LinkedHashSet) تا قدیمی‌ترین‌ها اول حذف شوند
      return raw.map((item) => item.toString()).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> save(Set<String> ids) async {
    try {
      await writeAtomicFile(await _file(), jsonEncode(ids.toList()));
    } catch (_) {}
  }
}
