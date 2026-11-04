import 'dart:io';

import 'package:sms_and_call/features/calls/data/call_settings.dart';
import 'package:sms_and_call/features/calls/data/recording_repository.dart';
import 'package:sms_and_call/features/calls/domain/call_models.dart';
import 'package:sms_and_call/features/calls/services/transcription.dart';

/// صف «تبدیل به متن و ارسال به سرور». هر ضبط مرحله‌به‌مرحله پیش می‌رود:
/// در صف ← در حال تبدیل ← متن آماده؛ و اگر خطای موقت بود با فاصله‌ی فزاینده دوباره.
class RecordingPipeline {
  RecordingPipeline({
    required this.repository,
    required this.settings,
    required this.speechToText,
    required this.uploader,
    DateTime Function()? clock,
    this.maxAttempts = 6,
    this.retryDelays = const [
      Duration(minutes: 2),
      Duration(minutes: 10),
      Duration(minutes: 30),
      Duration(hours: 2),
      Duration(hours: 6),
    ],
    this.lease = const Duration(minutes: 15),
  }) : _clock = clock ?? DateTime.now;

  final RecordingRepository repository;
  final CallSettings Function() settings;
  final Future<SpeechToText?> Function() speechToText;
  final Future<RemoteUploader?> Function() uploader;
  final int maxAttempts;
  final List<Duration> retryDelays;

  /// ضبطی که بیش از این مدت «در حال تبدیل» مانده، یعنی سرویس وسط کار مرده و دوباره صف می‌شود.
  final Duration lease;
  final DateTime Function() _clock;

  /// نوشته‌ی راهنما برای مدل: لحن گفتگوی تلفنی فارسی.
  static const String persianPrompt = 'این یک مکالمه‌ی تلفنی به زبان فارسی است.';

  bool _isDue(CallRecording r, DateTime now) {
    if (r.permanentFailure || !r.hasAudio) return false;
    switch (r.transcriptStatus) {
      case TranscriptStatus.queued:
        final next = r.nextAttemptAt;
        return next == null || !next.isAfter(now);
      case TranscriptStatus.failed:
        final next = r.nextAttemptAt;
        return next != null && !next.isAfter(now);
      case TranscriptStatus.running:
        final next = r.nextAttemptAt;
        return next != null && !next.isAfter(now); // مهلت (lease) تمام شده
      case TranscriptStatus.none:
      case TranscriptStatus.done:
        // فقط اگر ارسال به سرور مانده باشد
        final config = settings();
        return config.uploadConfigured &&
            r.uploadedAt == null &&
            r.attempts < maxAttempts;
    }
  }

  /// کارهای سررسیدشده را (حداکثر [max] ضبط) پردازش می‌کند. تعداد پردازش‌شده‌ها را برمی‌گرداند.
  Future<int> processDue({int max = 3}) async {
    final now = _clock();
    final due = (await repository.all()).where((r) => _isDue(r, now)).toList()
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    var processed = 0;
    for (final recording in due.take(max)) {
      await processOne(recording);
      processed++;
    }
    return processed;
  }

  /// آیا کاری برای انجام مانده؟ (برای تصمیم‌گیری درباره‌ی بیدار ماندن سرویس)
  Future<DateTime?> nextDueAt() async {
    final now = _clock();
    DateTime? best;
    for (final r in await repository.all()) {
      if (r.permanentFailure || !r.hasAudio) continue;
      DateTime? at;
      if (_isDue(r, now)) {
        at = now;
      } else if (r.nextAttemptAt != null) {
        at = r.nextAttemptAt;
      }
      if (at != null && (best == null || at.isBefore(best))) best = at;
    }
    return best;
  }

  Future<void> processOne(CallRecording recording) async {
    final config = settings();
    var current = recording;
    final started = _clock();
    // «ادعا» کردن ضبط: اگر ایزوله‌ی دیگری (سرویس یا رابط کاربری) همین الان رویش کار
    // می‌کند، رد می‌شویم تا یک ضبط دوبار تبدیل (و دوبار هزینه) نشود.
    final claimed = await repository.claim(
      recording.id,
      now: started,
      lease: lease,
    );
    if (claimed == null) return;
    current = claimed;

    final audio = File(current.audioPath);
    if (!await audio.exists()) {
      await _fail(current, 'فایل صوتی پیدا نشد.', retryable: false);
      return;
    }

    // متنِ قبلاً ساخته‌شده (مثلاً تبدیل موفق بود ولی ارسال به سرور خطا داد) دوباره
    // به سرویس پولی فرستاده نمی‌شود.
    var transcript = await repository.readTranscript(current.id);
    var provider = current.transcriptProvider;

    try {
      // ۱) تبدیل به متن
      if (transcript.isEmpty && config.canTranscribe) {
        final stt = await speechToText();
        if (stt == null) {
          await _fail(
            current,
            'سرویس تبدیل به متن تنظیم نشده یا کلید API وارد نشده است.',
            retryable: false,
          );
          return;
        }
        final result = await stt.transcribe(audio, prompt: config.language == 'fa' ? persianPrompt : null);
        transcript = result.text.trim();
        provider = stt.name;
        if (transcript.isEmpty) {
          await _fail(
            current,
            'سرویس متنی برنگرداند (شاید صدایی در فایل نبود).',
            retryable: false,
          );
          return;
        }
        await repository.writeTranscript(current.id, transcript);
        await repository.update(
          current.id,
          (r) => r.copyWith(
            transcriptStatus: TranscriptStatus.done,
            transcribedAt: _clock(),
            transcriptProvider: provider,
            transcriptError: '',
          ),
        );
      }

      // ۲) ارسال به سرور کاربر
      if (config.uploadConfigured && current.uploadedAt == null) {
        final remote = await uploader();
        if (remote != null) {
          final result = await remote.upload(
            metadata: _metadata(current),
            audio: config.uploadIncludeAudio ? audio : null,
            transcript: transcript,
          );
          if (transcript.isEmpty && result.transcript != null) {
            transcript = result.transcript!;
            provider = 'server';
            await repository.writeTranscript(current.id, transcript);
          }
          await repository.update(
            current.id,
            (r) => r.copyWith(
              uploadedAt: _clock(),
              transcriptStatus: transcript.isNotEmpty
                  ? TranscriptStatus.done
                  : (config.canTranscribe ? r.transcriptStatus : TranscriptStatus.none),
              transcribedAt: transcript.isNotEmpty && r.transcribedAt == null
                  ? _clock()
                  : r.transcribedAt,
              transcriptProvider: provider,
            ),
          );
        }
      }

      await repository.update(
        current.id,
        (r) => r.copyWith(
          // اگر هیچ مرحله‌ای کاری نداشت (نه تبدیل، نه ارسال) نباید «در حال تبدیل» بماند
          transcriptStatus: r.transcriptStatus == TranscriptStatus.running
              ? (transcript.isNotEmpty ? TranscriptStatus.done : TranscriptStatus.none)
              : r.transcriptStatus,
          transcriptError: '',
          attempts: 0,
          clearNextAttempt: true,
          permanentFailure: false,
        ),
      );
    } on TranscriptionException catch (e) {
      await _fail(current, e.message, retryable: e.retryable);
    } catch (e) {
      await _fail(current, 'خطای غیرمنتظره: $e', retryable: true);
    }
  }

  Map<String, String> _metadata(CallRecording r) => {
    'id': r.id,
    'number': r.number,
    'name': r.contactName,
    'direction': r.direction.name,
    'recordedAt': r.recordedAt.toIso8601String(),
    if (r.callStartedAt != null) 'callStartedAt': r.callStartedAt!.toIso8601String(),
    if (r.callDuration != null) 'callDurationSec': '${r.callDuration!.inSeconds}',
    'source': r.source.name,
    'brand': r.brand,
    'file': r.displayName,
  };

  Future<void> _fail(
    CallRecording recording,
    String message, {
    required bool retryable,
  }) async {
    final now = _clock();
    await repository.update(recording.id, (r) {
      final exhausted = r.attempts >= maxAttempts;
      final permanent = !retryable || exhausted;
      final delay = retryDelays[(r.attempts - 1).clamp(0, retryDelays.length - 1)];
      return r.copyWith(
        transcriptStatus: TranscriptStatus.failed,
        transcriptError: exhausted && retryable
            ? '$message (بعد از چند تلاش متوقف شد؛ دستی دوباره امتحان کنید)'
            : message,
        permanentFailure: permanent,
        nextAttemptAt: permanent ? null : now.add(delay),
        clearNextAttempt: permanent,
      );
    });
  }

  /// کاربر «دوباره تلاش» می‌زند: شمارنده و خطا پاک می‌شود و ضبط به صف برمی‌گردد.
  /// با [retranscribe] متن قبلی هم پاک می‌شود تا واقعاً دوباره تبدیل شود.
  Future<void> requeue(String id, {bool retranscribe = false}) async {
    if (retranscribe) await repository.clearTranscript(id);
    await repository.update(
      id,
      (r) => r.copyWith(
        transcriptStatus: TranscriptStatus.queued,
        transcriptError: '',
        attempts: 0,
        permanentFailure: false,
        clearNextAttempt: true,
      ),
    );
  }
}
