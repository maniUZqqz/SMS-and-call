import 'dart:convert';
import 'dart:io';

import 'package:sms_and_call/core/storage/app_storage.dart';
import 'package:sms_and_call/core/storage/file_mutex.dart';
import 'package:sms_and_call/features/contacts/domain/contact.dart';

enum OptOutSource { manual, contact, import }

/// یک شماره‌ی «لغو شده»: به این شماره دیگر هیچ پیامک کمپینی ارسال نمی‌شود.
class OptOutEntry {
  const OptOutEntry({
    required this.key,
    required this.phone,
    required this.addedAt,
    this.name = '',
    this.source = OptOutSource.manual,
  });

  /// [phoneKey] شماره؛ برای مقایسه.
  final String key;

  /// شماره به همان شکلی که ثبت شد (برای نمایش).
  final String phone;
  final String name;
  final DateTime addedAt;
  final OptOutSource source;

  factory OptOutEntry.create({
    required String phone,
    String name = '',
    OptOutSource source = OptOutSource.manual,
    DateTime? at,
  }) {
    final normalized = normalizePhoneNumber(phone);
    return OptOutEntry(
      key: phoneKey(normalized),
      phone: normalized,
      name: name.trim(),
      source: source,
      addedAt: at ?? DateTime.now(),
    );
  }

  factory OptOutEntry.fromJson(Map<String, dynamic> json) {
    final phone = (json['phone'] ?? '').toString();
    return OptOutEntry(
      key: phoneKey(phone),
      phone: phone,
      name: (json['name'] ?? '').toString(),
      addedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['addedAt'] as num?)?.toInt() ?? 0,
      ),
      source: OptOutSource.values.firstWhere(
        (value) => value.name == json['source'],
        orElse: () => OptOutSource.manual,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'phone': phone,
    'name': name,
    'addedAt': addedAt.millisecondsSinceEpoch,
    'source': source.name,
  };
}

/// فهرست لغو. جدا از مخاطبان نگه داشته می‌شود تا با حذف و واردکردن دوباره‌ی مخاطب
/// (مثلاً از همان فایل Excel قدیمی) دوباره فعال نشود.
class OptOutStorage {
  static Future<File> _file() async =>
      File('${await AppDir.path()}/sms_gateway_optout.json');

  static Future<FileMutex> _mutex() async =>
      FileMutex('${await AppDir.path()}/sms_gateway_optout.lock');

  static Future<List<OptOutEntry>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final raw = jsonDecode(content);
      if (raw is! List) return [];
      return raw
          .whereType<Map>()
          .map((item) => OptOutEntry.fromJson(Map<String, dynamic>.from(item)))
          .where((entry) => entry.key.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<Set<String>> loadKeys() async {
    return (await load()).map((entry) => entry.key).toSet();
  }

  /// شماره‌ها را اضافه می‌کند؛ شماره‌ی تکراری دوباره ثبت نمی‌شود.
  /// تعداد افزوده‌شده‌ها را برمی‌گرداند.
  static Future<int> addAll(Iterable<OptOutEntry> entries) async {
    var added = 0;
    await (await _mutex()).synchronized(() async {
      final current = await load();
      final known = current.map((entry) => entry.key).toSet();
      for (final entry in entries) {
        if (entry.key.isEmpty || !known.add(entry.key)) continue;
        current.add(entry);
        added++;
      }
      if (added > 0) await _write(current);
    });
    return added;
  }

  static Future<bool> add(OptOutEntry entry) async =>
      (await addAll([entry])) > 0;

  static Future<void> remove(String phone) async {
    final key = phoneKey(phone);
    await (await _mutex()).synchronized(() async {
      final current = await load();
      final next = current.where((entry) => entry.key != key).toList();
      if (next.length != current.length) await _write(next);
    });
  }

  static Future<void> _write(List<OptOutEntry> entries) async {
    await writeAtomicFile(
      await _file(),
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
  }
}

/// آیا مقدار یک ستونِ «وضعیت» در فایل Excel/CSV یعنی «لغو»؟
bool looksLikeOptOutMarker(String value) {
  final text = normalizeContactSearch(
    value,
  ).replaceAll(RegExp(r'[‌\s_\-]+'), '');
  if (text.isEmpty) return false;
  const markers = <String>{
    'لغو',
    'لغوشده',
    'لغوکرد',
    'لغوعضویت',
    'انصراف',
    'انصرافداد',
    'نمیخواهد',
    'نمیخوام',
    'ارسالنشود',
    'مسدود',
    'بلاک',
    'stop',
    'unsubscribe',
    'unsubscribed',
    'optout',
    'optedout',
    'cancel',
    'cancelled',
    'blocked',
    'dnc',
  };
  return markers.contains(text);
}
