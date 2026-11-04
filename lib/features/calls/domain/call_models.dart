import 'package:sms_bridge/sms_bridge.dart';

enum CallDirection { incoming, outgoing, missed, rejected, blocked, unknown }

/// مقدار `CallLog.Calls.TYPE` اندروید را به جهت تماس تبدیل می‌کند.
CallDirection callDirectionFromAndroid(int type) {
  switch (type) {
    case 1: // INCOMING
    case 4: // VOICEMAIL
    case 7: // ANSWERED_EXTERNALLY
      return CallDirection.incoming;
    case 2: // OUTGOING
      return CallDirection.outgoing;
    case 3: // MISSED
      return CallDirection.missed;
    case 5: // REJECTED
      return CallDirection.rejected;
    case 6: // BLOCKED
      return CallDirection.blocked;
    default:
      return CallDirection.unknown;
  }
}

String callDirectionLabel(CallDirection direction) {
  switch (direction) {
    case CallDirection.incoming:
      return 'ورودی';
    case CallDirection.outgoing:
      return 'خروجی';
    case CallDirection.missed:
      return 'بی‌پاسخ';
    case CallDirection.rejected:
      return 'ردشده';
    case CallDirection.blocked:
      return 'مسدود';
    case CallDirection.unknown:
      return 'نامشخص';
  }
}

/// یک تماس از تاریخچه‌ی گوشی.
class CallLogEntry {
  const CallLogEntry({
    required this.id,
    required this.number,
    required this.name,
    required this.startedAt,
    required this.duration,
    required this.direction,
  });

  final int id;
  final String number;
  final String name;
  final DateTime startedAt;
  final Duration duration;
  final CallDirection direction;

  DateTime get endedAt => startedAt.add(duration);

  factory CallLogEntry.fromRaw(RawCallLogEntry raw) => CallLogEntry(
    id: raw.id,
    number: raw.number,
    name: raw.name,
    startedAt: DateTime.fromMillisecondsSinceEpoch(raw.startedAtMillis),
    duration: Duration(seconds: raw.durationSeconds),
    direction: callDirectionFromAndroid(raw.type),
  );
}

enum RecordingSource {
  /// ضبط‌کننده‌ی خودِ گوشی/شماره‌گیر (پوشه‌ی ضبط تماس)
  phoneRecorder,

  /// ضبط‌کننده‌ی داخلی برنامه (سرویس دسترس‌پذیری، با میکروفون)
  inApp,

  /// فایل صوتی که کاربر دستی اضافه کرد یا ضبط دستی
  manual,
}

enum TranscriptStatus { none, queued, running, done, failed }

String transcriptStatusLabel(TranscriptStatus status) {
  switch (status) {
    case TranscriptStatus.none:
      return 'بدون متن';
    case TranscriptStatus.queued:
      return 'در صف تبدیل';
    case TranscriptStatus.running:
      return 'در حال تبدیل…';
    case TranscriptStatus.done:
      return 'متن آماده';
    case TranscriptStatus.failed:
      return 'تبدیل ناموفق';
  }
}

/// یک ضبط تماس ذخیره‌شده در برنامه.
class CallRecording {
  const CallRecording({
    required this.id,
    required this.audioPath,
    required this.sourceKey,
    required this.source,
    required this.recordedAt,
    required this.importedAt,
    this.displayName = '',
    this.brand = '',
    this.mime = '',
    this.sizeBytes = 0,
    this.durationMs = 0,
    this.number = '',
    this.contactName = '',
    this.direction = CallDirection.unknown,
    this.callStartedAt,
    this.callDuration,
    this.linked = false,
    this.transcriptStatus = TranscriptStatus.none,
    this.transcriptError = '',
    this.transcribedAt,
    this.transcriptProvider = '',
    this.attempts = 0,
    this.nextAttemptAt,
    this.uploadedAt,
    this.permanentFailure = false,
  });

  final String id;

  /// مسیر نسخه‌ی داخلی برنامه (خالی = فایل صوتی حذف شده و فقط متن مانده)
  final String audioPath;

  /// کلید یکتای منبع برای جلوگیری از واردکردن دوباره (مثلاً `ms:123`).
  final String sourceKey;
  final RecordingSource source;
  final DateTime recordedAt;
  final DateTime importedAt;
  final String displayName;
  final String brand;
  final String mime;
  final int sizeBytes;
  final int durationMs;
  final String number;
  final String contactName;
  final CallDirection direction;
  final DateTime? callStartedAt;
  final Duration? callDuration;

  /// به یک ردیف تاریخچه‌ی تماس وصل شده؟
  final bool linked;
  final TranscriptStatus transcriptStatus;
  final String transcriptError;
  final DateTime? transcribedAt;
  final String transcriptProvider;
  final int attempts;
  final DateTime? nextAttemptAt;
  final DateTime? uploadedAt;

  /// خطای دائمی (مثلاً کلید اشتباه): تا دخالت کاربر دوباره تلاش نمی‌شود.
  final bool permanentFailure;

  bool get hasAudio => audioPath.isNotEmpty;

  /// زمان تماس برای نمایش: شروع تماس اگر معلوم است، وگرنه زمان ضبط.
  DateTime get when => callStartedAt ?? recordedAt;

  String get title {
    if (contactName.trim().isNotEmpty) return contactName.trim();
    if (number.trim().isNotEmpty) return number.trim();
    return 'تماس ناشناس';
  }

  CallRecording copyWith({
    String? audioPath,
    String? number,
    String? contactName,
    CallDirection? direction,
    DateTime? callStartedAt,
    Duration? callDuration,
    bool? linked,
    int? durationMs,
    TranscriptStatus? transcriptStatus,
    String? transcriptError,
    DateTime? transcribedAt,
    String? transcriptProvider,
    int? attempts,
    DateTime? nextAttemptAt,
    bool clearNextAttempt = false,
    DateTime? uploadedAt,
    bool? permanentFailure,
  }) {
    return CallRecording(
      id: id,
      audioPath: audioPath ?? this.audioPath,
      sourceKey: sourceKey,
      source: source,
      recordedAt: recordedAt,
      importedAt: importedAt,
      displayName: displayName,
      brand: brand,
      mime: mime,
      sizeBytes: sizeBytes,
      durationMs: durationMs ?? this.durationMs,
      number: number ?? this.number,
      contactName: contactName ?? this.contactName,
      direction: direction ?? this.direction,
      callStartedAt: callStartedAt ?? this.callStartedAt,
      callDuration: callDuration ?? this.callDuration,
      linked: linked ?? this.linked,
      transcriptStatus: transcriptStatus ?? this.transcriptStatus,
      transcriptError: transcriptError ?? this.transcriptError,
      transcribedAt: transcribedAt ?? this.transcribedAt,
      transcriptProvider: transcriptProvider ?? this.transcriptProvider,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: clearNextAttempt
          ? null
          : (nextAttemptAt ?? this.nextAttemptAt),
      uploadedAt: uploadedAt ?? this.uploadedAt,
      permanentFailure: permanentFailure ?? this.permanentFailure,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'audioPath': audioPath,
    'sourceKey': sourceKey,
    'source': source.name,
    'recordedAt': recordedAt.millisecondsSinceEpoch,
    'importedAt': importedAt.millisecondsSinceEpoch,
    'displayName': displayName,
    'brand': brand,
    'mime': mime,
    'sizeBytes': sizeBytes,
    'durationMs': durationMs,
    'number': number,
    'contactName': contactName,
    'direction': direction.name,
    if (callStartedAt != null)
      'callStartedAt': callStartedAt!.millisecondsSinceEpoch,
    if (callDuration != null) 'callDurationSec': callDuration!.inSeconds,
    'linked': linked,
    'transcriptStatus': transcriptStatus.name,
    'transcriptError': transcriptError,
    if (transcribedAt != null)
      'transcribedAt': transcribedAt!.millisecondsSinceEpoch,
    'transcriptProvider': transcriptProvider,
    'attempts': attempts,
    if (nextAttemptAt != null)
      'nextAttemptAt': nextAttemptAt!.millisecondsSinceEpoch,
    if (uploadedAt != null) 'uploadedAt': uploadedAt!.millisecondsSinceEpoch,
    'permanentFailure': permanentFailure,
  };

  factory CallRecording.fromJson(Map<String, dynamic> json) {
    DateTime? at(dynamic v) =>
        v is num && v > 0 ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
    T pick<T extends Enum>(List<T> values, dynamic name, T fallback) {
      for (final value in values) {
        if (value.name == name) return value;
      }
      return fallback;
    }

    final durationSec = json['callDurationSec'];
    return CallRecording(
      id: (json['id'] ?? '').toString(),
      audioPath: (json['audioPath'] ?? '').toString(),
      sourceKey: (json['sourceKey'] ?? '').toString(),
      source: pick(
        RecordingSource.values,
        json['source'],
        RecordingSource.manual,
      ),
      recordedAt: at(json['recordedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      importedAt: at(json['importedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      displayName: (json['displayName'] ?? '').toString(),
      brand: (json['brand'] ?? '').toString(),
      mime: (json['mime'] ?? '').toString(),
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      number: (json['number'] ?? '').toString(),
      contactName: (json['contactName'] ?? '').toString(),
      direction: pick(
        CallDirection.values,
        json['direction'],
        CallDirection.unknown,
      ),
      callStartedAt: at(json['callStartedAt']),
      callDuration: durationSec is num ? Duration(seconds: durationSec.toInt()) : null,
      linked: json['linked'] == true,
      transcriptStatus: pick(
        TranscriptStatus.values,
        json['transcriptStatus'],
        TranscriptStatus.none,
      ),
      transcriptError: (json['transcriptError'] ?? '').toString(),
      transcribedAt: at(json['transcribedAt']),
      transcriptProvider: (json['transcriptProvider'] ?? '').toString(),
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      nextAttemptAt: at(json['nextAttemptAt']),
      uploadedAt: at(json['uploadedAt']),
      permanentFailure: json['permanentFailure'] == true,
    );
  }
}
