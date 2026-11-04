import 'dart:convert';
import 'dart:io';

import 'package:sms_and_call/core/storage/app_storage.dart';
import 'package:sms_and_call/core/storage/file_mutex.dart';
import 'package:sms_and_call/features/calls/domain/call_models.dart';
import 'package:sms_and_call/features/contacts/domain/contact.dart';

/// فیلتر فهرست ضبط‌ها.
enum RecordingFilter { all, withText, pending, failed, unlinked }

/// ذخیره‌ی محلیِ ضبط‌ها: یک فهرست JSON + فایل صوتی + یک فایل متن برای هر ضبط.
/// هم رابط کاربری و هم سرویس پس‌زمینه از آن می‌نویسند، پس نوشتن‌ها با [FileMutex] قفل می‌شوند.
class RecordingRepository {
  RecordingRepository({String? rootPath}) : _rootOverride = rootPath;

  final String? _rootOverride;
  final Map<String, String> _searchCache = <String, String>{};

  Future<Directory> _root() async {
    final base = _rootOverride ?? '${await AppDir.path()}/call_recordings';
    final dir = Directory(base);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<String> audioDirPath() async {
    final dir = Directory('${(await _root()).path}/audio');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<File> _index() async => File('${(await _root()).path}/index.json');

  Future<FileMutex> _mutex() async =>
      FileMutex('${(await _root()).path}/index.lock');

  Future<File> _transcriptFile(String id) async {
    final dir = Directory('${(await _root()).path}/transcripts');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/$id.txt');
  }

  Future<List<CallRecording>> all() async {
    try {
      final file = await _index();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final raw = jsonDecode(content);
      if (raw is! List) return [];
      final items = raw
          .whereType<Map>()
          .map((e) => CallRecording.fromJson(Map<String, dynamic>.from(e)))
          .where((item) => item.id.isNotEmpty)
          .toList();
      items.sort((a, b) => b.when.compareTo(a.when));
      return items;
    } catch (_) {
      return [];
    }
  }

  Future<CallRecording?> get(String id) async {
    for (final item in await all()) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<bool> hasSourceKey(String key) async {
    for (final item in await all()) {
      if (item.sourceKey == key) return true;
    }
    return false;
  }

  /// تغییر روی یک ضبط را به‌صورت اتمیک (خواندن ← تغییر ← نوشتن) اعمال می‌کند.
  Future<CallRecording?> update(
    String id,
    CallRecording Function(CallRecording current) change,
  ) async {
    CallRecording? result;
    await (await _mutex()).synchronized(() async {
      final items = await all();
      final index = items.indexWhere((item) => item.id == id);
      if (index < 0) return;
      result = change(items[index]);
      items[index] = result!;
      await _write(items);
    });
    return result;
  }

  /// ضبط را برای پردازش «ادعا» می‌کند (وضعیت ← در حال تبدیل، با مهلت). اگر کس دیگری
  /// با مهلتِ منقضی‌نشده روی آن کار می‌کند، null برمی‌گرداند.
  Future<CallRecording?> claim(
    String id, {
    required DateTime now,
    required Duration lease,
  }) async {
    CallRecording? result;
    await (await _mutex()).synchronized(() async {
      final items = await all();
      final index = items.indexWhere((item) => item.id == id);
      if (index < 0) return;
      final current = items[index];
      final until = current.nextAttemptAt;
      if (current.transcriptStatus == TranscriptStatus.running &&
          until != null &&
          until.isAfter(now)) {
        return;
      }
      result = current.copyWith(
        transcriptStatus: TranscriptStatus.running,
        attempts: current.attempts + 1,
        nextAttemptAt: now.add(lease),
        transcriptError: '',
      );
      items[index] = result!;
      await _write(items);
    });
    return result;
  }

  Future<void> upsert(CallRecording recording) async {
    await (await _mutex()).synchronized(() async {
      final items = await all();
      final index = items.indexWhere((item) => item.id == recording.id);
      if (index < 0) {
        items.add(recording);
      } else {
        items[index] = recording;
      }
      await _write(items);
    });
  }

  /// اگر کلید منبع تکراری نباشد اضافه می‌کند؛ نتیجه: آیا اضافه شد؟
  Future<bool> addIfNew(CallRecording recording) async {
    var added = false;
    await (await _mutex()).synchronized(() async {
      final items = await all();
      if (items.any((item) => item.sourceKey == recording.sourceKey)) return;
      items.add(recording);
      await _write(items);
      added = true;
    });
    return added;
  }

  /// ضبط را حذف می‌کند. با [deleteAudio] فایل صوتی پاک می‌شود؛ با [deleteTranscript]
  /// متن. اگر هر دو پاک شوند، ردیف هم از فهرست حذف می‌شود. اگر فقط صدا پاک شود،
  /// متن و اطلاعات تماس می‌ماند.
  Future<void> delete(
    String id, {
    bool deleteAudio = true,
    bool deleteTranscript = true,
  }) async {
    await (await _mutex()).synchronized(() async {
      final items = await all();
      final index = items.indexWhere((item) => item.id == id);
      if (index < 0) return;
      final item = items[index];
      if (deleteAudio && item.audioPath.isNotEmpty) {
        try {
          final audio = File(item.audioPath);
          if (await audio.exists()) await audio.delete();
        } catch (_) {}
      }
      if (deleteTranscript) {
        try {
          final text = await _transcriptFile(id);
          if (await text.exists()) await text.delete();
        } catch (_) {}
        _searchCache.remove(id);
      }
      if (deleteAudio && deleteTranscript) {
        items.removeAt(index);
      } else if (deleteAudio) {
        items[index] = CallRecording(
          id: item.id,
          audioPath: '',
          sourceKey: item.sourceKey,
          source: item.source,
          recordedAt: item.recordedAt,
          importedAt: item.importedAt,
          displayName: item.displayName,
          brand: item.brand,
          mime: item.mime,
          sizeBytes: 0,
          durationMs: item.durationMs,
          number: item.number,
          contactName: item.contactName,
          direction: item.direction,
          callStartedAt: item.callStartedAt,
          callDuration: item.callDuration,
          linked: item.linked,
          transcriptStatus: item.transcriptStatus,
          transcriptError: item.transcriptError,
          transcribedAt: item.transcribedAt,
          transcriptProvider: item.transcriptProvider,
          attempts: item.attempts,
          uploadedAt: item.uploadedAt,
        );
      } else {
        items[index] = item.copyWith(
          transcriptStatus: TranscriptStatus.none,
          transcriptError: '',
          clearNextAttempt: true,
        );
      }
      await _write(items);
    });
  }

  Future<String> readTranscript(String id) async {
    try {
      final file = await _transcriptFile(id);
      if (!await file.exists()) return '';
      return await file.readAsString();
    } catch (_) {
      return '';
    }
  }

  /// فقط فایل متن را پاک می‌کند (ردیف و صدا می‌مانند).
  Future<void> clearTranscript(String id) async {
    try {
      final file = await _transcriptFile(id);
      if (await file.exists()) await file.delete();
    } catch (_) {}
    _searchCache.remove(id);
  }

  Future<void> writeTranscript(String id, String text) async {
    final file = await _transcriptFile(id);
    await writeAtomicFile(file, text);
    _searchCache[id] = normalizeSearchText(text);
  }

  Future<void> _write(List<CallRecording> items) async {
    await writeAtomicFile(
      await _index(),
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  /// جست‌وجو در نام، شماره و متنِ تبدیل‌شده (با یکسان‌سازی ی/ک و ارقام فارسی).
  Future<List<CallRecording>> search(
    String query, {
    RecordingFilter filter = RecordingFilter.all,
  }) async {
    var items = await all();
    items = items.where((item) => _passes(item, filter)).toList();
    final q = normalizeSearchText(query);
    if (q.isEmpty) return items;
    final digits = normalizePhoneNumber(query);
    final result = <CallRecording>[];
    for (final item in items) {
      final head = normalizeSearchText('${item.contactName} ${item.number}');
      if (head.contains(q) ||
          (digits.length >= 3 && item.number.contains(digits))) {
        result.add(item);
        continue;
      }
      if (item.transcriptStatus != TranscriptStatus.done) continue;
      var text = _searchCache[item.id];
      if (text == null) {
        text = normalizeSearchText(await readTranscript(item.id));
        _searchCache[item.id] = text;
      }
      if (text.contains(q)) result.add(item);
    }
    return result;
  }

  bool _passes(CallRecording item, RecordingFilter filter) {
    switch (filter) {
      case RecordingFilter.all:
        return true;
      case RecordingFilter.withText:
        return item.transcriptStatus == TranscriptStatus.done;
      case RecordingFilter.pending:
        return item.transcriptStatus == TranscriptStatus.queued ||
            item.transcriptStatus == TranscriptStatus.running;
      case RecordingFilter.failed:
        return item.transcriptStatus == TranscriptStatus.failed;
      case RecordingFilter.unlinked:
        return !item.linked;
    }
  }
}

/// متن را برای جست‌وجو یکسان می‌کند: ی/ک عربی، اعراب، ارقام فارسی/عربی، فاصله‌ها.
String normalizeSearchText(String value) {
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  var text = normalizeContactSearch(value);
  for (var i = 0; i < 10; i++) {
    text = text.replaceAll(persian[i], '$i').replaceAll(arabic[i], '$i');
  }
  return text.replaceAll('‌', ' ').replaceAll(RegExp(r'\s+'), ' ');
}
