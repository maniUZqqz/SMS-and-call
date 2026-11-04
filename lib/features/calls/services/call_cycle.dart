import 'dart:async';

import 'package:sms_and_call/core/storage/app_storage.dart';
import 'package:sms_and_call/features/calls/data/call_settings.dart';
import 'package:sms_and_call/features/calls/data/recording_repository.dart';
import 'package:sms_and_call/features/calls/services/recording_pipeline.dart';
import 'package:sms_and_call/features/calls/services/recording_scanner.dart';
import 'package:sms_and_call/features/calls/services/transcription.dart';

/// نام پوشه‌ی ضبط داخلی (باید با سمت بومی یکی باشد).
const String kInAppRecordingsFolder = 'inapp_recordings';

class CycleReport {
  const CycleReport({
    this.scan,
    this.processed = 0,
    this.nextDueAt,
    this.skipped = false,
  });

  final ScanReport? scan;
  final int processed;

  /// اگر کاری مانده (مثلاً تلاش دوباره‌ی یک ضبط)، زمان سررسید آن.
  final DateTime? nextDueAt;

  /// چرخه اجرا نشد (هنوز راه‌اندازی/پذیرش اطلاعیه انجام نشده).
  final bool skipped;
}

/// یک «چرخه»: ضبط‌های تازه را پیدا و وارد کن ← به تماس وصل کن ← به متن تبدیل کن
/// ← (اختیاری) به سرور بفرست. هم سرویس پس‌زمینه و هم صفحه‌ی ضبط‌ها همین را اجرا می‌کنند.
class CallCycle {
  CallCycle({
    CallPlatform? platform,
    RecordingRepository? repository,
    this.timeBudget = const Duration(minutes: 8),
  }) : platform = platform ?? const SmsBridgeCallPlatform(),
       repository = repository ?? RecordingRepository();

  final CallPlatform platform;
  final RecordingRepository repository;

  /// بیشینه‌ی زمانی که یک چرخه‌ی پردازش صف می‌تواند ادامه دهد.
  final Duration timeBudget;

  static bool _running = false;
  static bool get isRunning => _running;

  Future<CycleReport> run({bool scan = true, bool process = true}) async {
    if (_running) return const CycleReport(skipped: true);
    _running = true;
    try {
      var settings = await CallSettingsStorage.load();
      if (!settings.consentAccepted) return const CycleReport(skipped: true);

      ScanReport? report;
      if (scan && (settings.watchPhoneRecorder || settings.inAppRecorderEnabled)) {
        final dir = '${await AppDir.path()}/$kInAppRecordingsFolder';
        final scanner = RecordingScanner(
          platform: platform,
          repository: repository,
          settings: () => settings,
          inAppDirPath: dir,
        );
        report = await scanner.scan();
        final safe = report.safeUntil;
        if (safe != null) {
          await CallSettingsStorage.update(
            (current) => current.copyWith(
              lastScanAtMillis: safe.millisecondsSinceEpoch,
            ),
          );
          settings = await CallSettingsStorage.load();
        }
      }

      var processed = 0;
      DateTime? next;
      if (process) {
        await refreshSettings();
        final pipeline = buildPipeline();
        final deadline = DateTime.now().add(timeBudget);
        while (DateTime.now().isBefore(deadline)) {
          await refreshSettings(); // کاربر ممکن است وسط کار تنظیمات را عوض کرده باشد
          final count = await pipeline.processDue(max: 1);
          if (count == 0) break;
          processed += count;
        }
        next = await pipeline.nextDueAt();
      }
      return CycleReport(scan: report, processed: processed, nextDueAt: next);
    } finally {
      _running = false;
    }
  }

  RecordingPipeline buildPipeline() {
    return RecordingPipeline(
      repository: repository,
      settings: _latestSettings,
      speechToText: _speechToText,
      uploader: _uploader,
    );
  }

  // تنظیمات در هر چرخه‌ی پردازش تازه خوانده می‌شود (کاربر ممکن است وسط کار عوضشان کند).
  CallSettings _cached = const CallSettings();
  CallSettings _latestSettings() => _cached;

  /// پیش از [RecordingPipeline.processDue] صدا زده می‌شود تا تنظیمات به‌روز باشد.
  Future<void> refreshSettings() async {
    _cached = await CallSettingsStorage.load();
  }

  Future<SpeechToText?> _speechToText() async {
    final settings = await CallSettingsStorage.load();
    _cached = settings;
    if (!settings.canTranscribe) return null;
    try {
      final key = await CallSecrets.readSttKey();
      return OpenAiCompatibleTranscriber(
        baseUrl: settings.sttBaseUrl,
        apiKey: key,
        model: settings.sttModel,
        language: settings.language,
      );
    } on FormatException {
      return null;
    }
  }

  Future<RemoteUploader?> _uploader() async {
    final settings = await CallSettingsStorage.load();
    _cached = settings;
    if (!settings.uploadEnabled || settings.uploadUrl.trim().isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(settings.uploadUrl.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return RemoteUploader(url: uri, token: await CallSecrets.readUploadToken());
  }
}
