import 'dart:convert';
import 'dart:io';

import 'package:sms_bridge/sms_bridge.dart';
import 'package:sms_and_call/features/calls/data/call_settings.dart';
import 'package:sms_and_call/features/calls/data/recording_repository.dart';
import 'package:sms_and_call/features/calls/domain/call_models.dart';
import 'package:sms_and_call/features/calls/domain/recording_matcher.dart';

/// دسترسی به دنیای اندروید (تاریخچه‌ی تماس و فایل‌های صوتی). برای تست با نسخه‌ی جعلی
/// جایگزین می‌شود.
abstract interface class CallPlatform {
  Future<List<RawAudioFile>> audioSince(DateTime since, {int limit});
  Future<List<RawCallLogEntry>> callsSince(DateTime since, {int limit});
  Future<String?> copyUri(String uri, String destination);
}

class SmsBridgeCallPlatform implements CallPlatform {
  const SmsBridgeCallPlatform();

  @override
  Future<List<RawAudioFile>> audioSince(DateTime since, {int limit = 500}) =>
      SmsBridge.queryAudioFiles(
        sinceMillis: since.millisecondsSinceEpoch,
        limit: limit,
      );

  @override
  Future<List<RawCallLogEntry>> callsSince(DateTime since, {int limit = 500}) =>
      SmsBridge.queryCallLog(
        sinceMillis: since.millisecondsSinceEpoch,
        limit: limit,
      );

  @override
  Future<String?> copyUri(String uri, String destination) =>
      SmsBridge.copyUriToFile(uri: uri, destinationPath: destination);
}

class ScanReport {
  const ScanReport({
    this.imported = 0,
    this.linked = 0,
    this.relinked = 0,
    this.deferred = 0,
    this.safeUntil,
  });

  /// ضبط‌های تازه که وارد برنامه شدند.
  final int imported;

  /// از آن‌ها، چند ضبط به یک تماس تاریخچه وصل شد.
  final int linked;

  /// ضبط‌های قبلاً واردشده که حالا به تماسشان وصل شدند.
  final int relinked;

  /// فایل‌هایی که هنوز در حال نوشته‌شدن بودند و دور بعد بررسی می‌شوند.
  final int deferred;

  /// تا این زمان همه‌چیز بررسی شده؛ اسکن بعدی از همین‌جا (با کمی هم‌پوشانی) شروع می‌شود.
  final DateTime? safeUntil;
}

/// پوشه‌ی ضبط‌کننده‌ی گوشی و پوشه‌ی ضبط داخلی را بررسی می‌کند، ضبط‌های تازه را
/// به برنامه می‌آورد و به تماسِ متناظر در تاریخچه وصل می‌کند.
class RecordingScanner {
  RecordingScanner({
    required this.platform,
    required this.repository,
    required this.settings,
    this.inAppDirPath,
    DateTime Function()? clock,
    this.settleTime = const Duration(seconds: 20),
    this.overlap = const Duration(minutes: 15),
  }) : _clock = clock ?? DateTime.now;

  final CallPlatform platform;
  final RecordingRepository repository;
  final CallSettings Function() settings;
  final String? inAppDirPath;
  final DateTime Function() _clock;

  /// فایلی که تازه‌تر از این تغییر کرده، شاید هنوز در حال نوشته شدن باشد.
  final Duration settleTime;

  /// اسکن هر بار کمی عقب‌تر از آخرین اسکن شروع می‌شود تا فایل‌های دیررس جا نمانند.
  final Duration overlap;

  static int _counter = 0;

  String _newId(DateTime now) =>
      'r${now.microsecondsSinceEpoch.toRadixString(36)}${(_counter++).toRadixString(36)}';

  Future<ScanReport> scan() async {
    final config = settings();
    final now = _clock();
    final since = config.lastScanAtMillis > 0
        ? DateTime.fromMillisecondsSinceEpoch(
            config.lastScanAtMillis,
          ).subtract(overlap)
        : now.subtract(Duration(days: config.importDays));

    var imported = 0;
    var linked = 0;
    var deferred = 0;
    DateTime? safeUntil = now;

    final known = (await repository.all()).map((r) => r.sourceKey).toSet();
    final pending = <_Incoming>[];

    // ۱) ضبط‌کننده‌ی خودِ گوشی
    if (config.watchPhoneRecorder) {
      const cap = 800;
      final files = await platform.audioSince(since, limit: cap);
      files.sort((a, b) => a.dateAddedMillis.compareTo(b.dateAddedMillis));
      if (files.length >= cap) {
        // به سقف رسیدیم؛ قدیمی‌ترین‌ها اول پردازش می‌شوند و ادامه در اسکن بعد است
        final last = DateTime.fromMillisecondsSinceEpoch(files.last.dateAddedMillis);
        if (last.isBefore(safeUntil)) safeUntil = last;
      }
      for (final file in files) {
        final match = matchRecordingFolder(
          relativePath: file.relativePath,
          displayName: file.displayName,
        );
        if (match == null || !match.isConfident) continue;
        final key = 'ms:${file.id}';
        if (known.contains(key)) continue;
        if (file.sizeBytes > 0 && file.sizeBytes < 2048) continue;
        final modified = file.dateModifiedMillis > 0
            ? DateTime.fromMillisecondsSinceEpoch(file.dateModifiedMillis)
            : DateTime.fromMillisecondsSinceEpoch(file.dateAddedMillis);
        if (now.difference(modified) < settleTime) {
          deferred++;
          if (safeUntil != null && modified.isBefore(safeUntil)) {
            safeUntil = modified;
          }
          continue;
        }
        pending.add(
          _Incoming(
            key: key,
            source: RecordingSource.phoneRecorder,
            brand: match.brand.name,
            displayName: file.displayName,
            mime: file.mime,
            sizeBytes: file.sizeBytes,
            durationMs: file.durationMs,
            recordedAt: modified,
            times: [
              modified,
              DateTime.fromMillisecondsSinceEpoch(file.dateAddedMillis),
            ],
            uri: file.uri,
          ),
        );
      }
    }

    // ۲) ضبط‌کننده‌ی داخلی برنامه
    pending.addAll(await _inAppFiles(known, now));

    List<CallLogEntry> calls = const [];
    if (pending.isNotEmpty || await _hasUnlinked(now)) {
      calls = await _loadCalls(
        pending.map((p) => p.recordedAt).toList(),
        now,
      );
    }

    final audioDir = await repository.audioDirPath();
    for (final item in pending) {
      final id = _newId(now);
      final ext = _extensionOf(item.displayName, item.mime);
      final destination = '$audioDir/$id.$ext';

      if (item.uri != null) {
        final copied = await platform.copyUri(item.uri!, destination);
        if (copied == null || !await File(copied).exists()) {
          // کپی نشد: در اسکن بعد دوباره امتحان شود (ساعت اسکن از این فایل جلوتر نمی‌رود)
          deferred++;
          if (safeUntil != null && item.recordedAt.isBefore(safeUntil)) {
            safeUntil = item.recordedAt;
          }
          continue;
        }
      } else {
        try {
          await File(item.localPath!).rename(destination);
        } on FileSystemException {
          await File(item.localPath!).copy(destination);
          try {
            await File(item.localPath!).delete();
          } catch (_) {}
        }
        if (item.sidecarPath != null) {
          try {
            await File(item.sidecarPath!).delete();
          } catch (_) {}
        }
      }

      final recording = _build(
        id: id,
        item: item,
        destination: destination,
        calls: calls,
        now: now,
        config: config,
      );
      if (await repository.addIfNew(recording)) {
        imported++;
        if (recording.linked) linked++;
      } else {
        try {
          await File(destination).delete();
        } catch (_) {}
      }
    }

    final relinked = await _relink(calls, now);
    return ScanReport(
      imported: imported,
      linked: linked,
      relinked: relinked,
      deferred: deferred,
      safeUntil: safeUntil,
    );
  }

  CallRecording _build({
    required String id,
    required _Incoming item,
    required String destination,
    required List<CallLogEntry> calls,
    required DateTime now,
    required CallSettings config,
  }) {
    final parsed = parseRecordingName(item.displayName);
    final number = item.knownNumber.isNotEmpty ? item.knownNumber : parsed.number;
    final times = <DateTime>[...item.times, if (parsed.when != null) parsed.when!];
    final match = findCallForRecording(
      times: times,
      calls: calls,
      parsedNumber: number,
    );
    final call = match?.call;
    return CallRecording(
      id: id,
      audioPath: destination,
      sourceKey: item.key,
      source: item.source,
      recordedAt: item.recordedAt,
      importedAt: now,
      displayName: item.displayName,
      brand: item.brand,
      mime: item.mime,
      sizeBytes: item.sizeBytes,
      durationMs: item.durationMs,
      number: call != null && call.number.isNotEmpty ? call.number : number,
      contactName: call != null && call.name.isNotEmpty ? call.name : parsed.name,
      direction: call?.direction ?? item.knownDirection,
      callStartedAt: call?.startedAt,
      callDuration: call?.duration,
      linked: call != null,
      transcriptStatus: config.autoTranscribe && config.hasAnyOutput
          ? TranscriptStatus.queued
          : TranscriptStatus.none,
    );
  }

  Future<bool> _hasUnlinked(DateTime now) async {
    final cutoff = now.subtract(const Duration(days: 3));
    return (await repository.all()).any(
      (r) => !r.linked && r.recordedAt.isAfter(cutoff),
    );
  }

  Future<List<CallLogEntry>> _loadCalls(List<DateTime> times, DateTime now) async {
    var earliest = now.subtract(const Duration(days: 3));
    for (final time in times) {
      final candidate = time.subtract(const Duration(days: 1));
      if (candidate.isBefore(earliest)) earliest = candidate;
    }
    final raw = await platform.callsSince(earliest, limit: 1000);
    return raw.map(CallLogEntry.fromRaw).toList();
  }

  /// ضبط‌هایی که هنگام واردشدن تماسشان در تاریخچه نبود (اندروید گاهی ردیف را دیرتر می‌نویسد).
  Future<int> _relink(List<CallLogEntry> calls, DateTime now) async {
    final cutoff = now.subtract(const Duration(days: 3));
    var count = 0;
    for (final recording in await repository.all()) {
      if (recording.linked || !recording.recordedAt.isAfter(cutoff)) continue;
      if (calls.isEmpty) break;
      final parsed = parseRecordingName(recording.displayName);
      final match = findCallForRecording(
        times: [recording.recordedAt, if (parsed.when != null) parsed.when!],
        calls: calls,
        parsedNumber: recording.number.isNotEmpty ? recording.number : parsed.number,
      );
      final call = match?.call;
      if (call == null) continue;
      await repository.update(
        recording.id,
        (current) => current.copyWith(
          number: call.number.isNotEmpty ? call.number : current.number,
          contactName: call.name.isNotEmpty ? call.name : current.contactName,
          direction: call.direction,
          callStartedAt: call.startedAt,
          callDuration: call.duration,
          linked: true,
        ),
      );
      count++;
    }
    return count;
  }

  Future<List<_Incoming>> _inAppFiles(Set<String> known, DateTime now) async {
    final path = inAppDirPath;
    if (path == null || path.isEmpty) return const [];
    final dir = Directory(path);
    if (!await dir.exists()) return const [];
    final result = <_Incoming>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!hasAudioExtension(name)) continue;
      final key = 'inapp:$name';
      if (known.contains(key)) continue;
      final stat = await entity.stat();
      if (now.difference(stat.modified) < settleTime) continue; // هنوز در حال ضبط
      if (stat.size < 1024) {
        try {
          await entity.delete(); // ضبط خالی/ناموفق
        } catch (_) {}
        continue;
      }
      final sidecar = File('${entity.path.substring(0, entity.path.lastIndexOf('.'))}.json');
      var meta = <String, dynamic>{};
      if (await sidecar.exists()) {
        try {
          meta = Map<String, dynamic>.from(jsonDecode(await sidecar.readAsString()) as Map);
        } catch (_) {}
      }
      if (meta['silent'] == true) {
        // میکروفون در زمان تماس به برنامه صدایی نداده؛ فایل بی‌صدا فایده‌ای ندارد
        try {
          await entity.delete();
          if (await sidecar.exists()) await sidecar.delete();
        } catch (_) {}
        continue;
      }
      DateTime? at(dynamic v) =>
          v is num && v > 0 ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
      final startedAt = at(meta['startedAt']);
      final endedAt = at(meta['endedAt']) ?? stat.modified;
      result.add(
        _Incoming(
          key: key,
          source: meta['source'] == 'manual'
              ? RecordingSource.manual
              : RecordingSource.inApp,
          brand: 'inapp',
          displayName: name,
          mime: '',
          sizeBytes: stat.size,
          durationMs: (meta['durationMs'] as num?)?.toInt() ?? 0,
          recordedAt: endedAt,
          times: [endedAt, if (startedAt != null) startedAt],
          localPath: entity.path,
          sidecarPath: await sidecar.exists() ? sidecar.path : null,
          knownNumber: (meta['number'] ?? '').toString(),
          knownDirection: switch (meta['direction']) {
            'incoming' => CallDirection.incoming,
            'outgoing' => CallDirection.outgoing,
            _ => CallDirection.unknown,
          },
        ),
      );
    }
    return result;
  }

  String _extensionOf(String name, String mime) {
    final dot = name.lastIndexOf('.');
    if (dot > 0 && dot < name.length - 1) {
      final ext = name.substring(dot + 1).toLowerCase();
      if (RegExp(r'^[a-z0-9]{2,5}$').hasMatch(ext)) return ext;
    }
    if (mime.contains('mpeg')) return 'mp3';
    if (mime.contains('amr')) return 'amr';
    if (mime.contains('wav')) return 'wav';
    if (mime.contains('ogg')) return 'ogg';
    return 'm4a';
  }
}

class _Incoming {
  const _Incoming({
    required this.key,
    required this.source,
    required this.brand,
    required this.displayName,
    required this.mime,
    required this.sizeBytes,
    required this.durationMs,
    required this.recordedAt,
    required this.times,
    this.uri,
    this.localPath,
    this.sidecarPath,
    this.knownNumber = '',
    this.knownDirection = CallDirection.unknown,
  });

  final String key;
  final RecordingSource source;
  final String brand;
  final String displayName;
  final String mime;
  final int sizeBytes;
  final int durationMs;
  final DateTime recordedAt;
  final List<DateTime> times;
  final String? uri;
  final String? localPath;
  final String? sidecarPath;
  final String knownNumber;
  final CallDirection knownDirection;
}
