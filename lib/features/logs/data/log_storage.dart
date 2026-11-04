import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:untitled3/core/storage/app_storage.dart';
import 'package:untitled3/features/logs/domain/log_entry.dart';

class LogStorage {
  static bool _writing = false;
  static List<Map<String, dynamic>>? _pending;
  static Timer? _timer;
  static List<LogEntry>? _latest;

  static Future<File> _file() async =>
      File('${await AppDir.path()}/sms_gateway_logs.json');

  static Future<List<LogEntry>> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return [];
      final content = await f.readAsString();
      if (content.trim().isEmpty) return [];
      final list = jsonDecode(content) as List;
      return list
          .map((e) => LogEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static void save(List<LogEntry> items) {
    _latest = items;
    _timer ??= Timer(const Duration(milliseconds: 1000), () {
      _timer = null;
      final l = _latest;
      if (l != null) _write(l);
    });
  }

  static Future<void> flush(List<LogEntry> items) async {
    _timer?.cancel();
    _timer = null;
    await _write(items);
  }

  static Future<void> _write(List<LogEntry> items) async {
    _pending = items.map((e) => e.toJson()).toList();
    if (_writing) return;
    _writing = true;
    try {
      while (_pending != null) {
        final data = _pending!;
        _pending = null;
        final f = await _file();
        await writeAtomicFile(f, jsonEncode(data));
      }
    } catch (_) {
    } finally {
      _writing = false;
    }
  }

  static Future<void> clear() async {
    try {
      _timer?.cancel();
      _timer = null;
      _latest = null;
      _pending = null;
      final f = await _file();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  static List<LogEntry> closeStale(List<LogEntry> items) {
    final changed = <LogEntry>[];
    for (final e in items) {
      var touched = false;
      for (final s in e.steps) {
        if (s.state == StepState.pending) {
          s.update(StepState.warn, detail: 'ناتمام ماند (سرویس متوقف شد)');
          touched = true;
        }
      }
      if (touched) changed.add(e);
    }
    return changed;
  }
}
