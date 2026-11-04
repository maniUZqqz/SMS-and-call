import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sms_bridge/sms_bridge.dart';
import 'package:sms_and_call/features/settings/domain/server_config.dart';

class AppDir {
  static String? _cached;

  static Future<String> path() async {
    final c = _cached;
    if (c != null) return c;
    String p = '';
    try {
      p = await SmsBridge.filesDir();
    } catch (_) {}
    if (p.isEmpty) p = Directory.systemTemp.path;
    _cached = p;
    return p;
  }

  /// فقط برای تست‌ها: پوشهٔ داده را عوض می‌کند (null = بازگشت به حالت عادی).
  @visibleForTesting
  static void setPathForTests(String? value) => _cached = value;
}

int _tmpCounter = 0;

Future<void> writeAtomicFile(File f, String data) async {
  // نام موقتِ یکتا: رابط کاربری و سرویس هم‌زمان روی یک فایل می‌نویسند و نباید
  // روی فایل موقتِ هم تکیه کنند (rename دومی خطا می‌داد و کمپین «ناموفق» ثبت می‌شد).
  final tmp = File(
    '${f.path}.${DateTime.now().microsecondsSinceEpoch}-${_tmpCounter++}.tmp',
  );
  await tmp.writeAsString(data, flush: true);
  await tmp.rename(f.path);
}

class ConfigStorage {
  static Future<File> _file() async =>
      File('${await AppDir.path()}/sms_gateway_config.json');

  static Future<ServerConfig> load() async {
    try {
      var file = await _file();
      if (!await file.exists()) {
        // مهاجرت از مسیر قدیمی (cache)
        final old = File(
          '${Directory.systemTemp.path}/sms_gateway_config.json',
        );
        if (await old.exists()) file = old;
      }
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          return ServerConfig.fromJson(
            jsonDecode(content) as Map<String, dynamic>,
          );
        }
      }
    } catch (_) {}
    return ServerConfig.defaults();
  }

  static Future<void> save(ServerConfig config) async {
    try {
      final file = await _file();
      await writeAtomicFile(file, jsonEncode(config.toJson()));
    } catch (_) {}
  }
}
