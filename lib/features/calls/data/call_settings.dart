import 'dart:convert';
import 'dart:io';

import 'package:sms_bridge/sms_bridge.dart';
import 'package:sms_and_call/core/storage/app_storage.dart';
import 'package:sms_and_call/core/storage/file_mutex.dart';

enum TranscriptionProvider { none, openAiCompatible }

/// تنظیمات ضبط تماس، تبدیل به متن و ارسال به سرور. کلیدها و توکن‌ها اینجا نیستند؛
/// آن‌ها با [CallSecrets] در حافظه‌ی رمزشده‌ی اندروید (Keystore) می‌مانند.
class CallSettings {
  const CallSettings({
    this.consentAcceptedAt,
    this.setupCompleted = false,
    this.watchPhoneRecorder = true,
    this.inAppRecorderEnabled = false,
    this.autoSpeaker = false,
    this.autoTranscribe = true,
    this.provider = TranscriptionProvider.none,
    this.sttBaseUrl = 'https://api.openai.com/v1',
    this.sttModel = 'whisper-1',
    this.language = 'fa',
    this.uploadEnabled = false,
    this.uploadUrl = '',
    this.uploadIncludeAudio = true,
    this.lastScanAtMillis = 0,
    this.importDays = 7,
  });

  /// کاربر اطلاعیه‌ی مسئولیت ضبط تماس را پذیرفته است (زمان پذیرش).
  final DateTime? consentAcceptedAt;

  /// راه‌اندازی اولیه (راهنمای مرحله‌به‌مرحله) انجام شده است.
  final bool setupCompleted;

  /// پوشه‌ی ضبط‌کننده‌ی خودِ گوشی رصد شود.
  final bool watchPhoneRecorder;

  /// ضبط‌کننده‌ی داخلی (سرویس دسترس‌پذیری) فعال باشد.
  final bool inAppRecorderEnabled;

  /// هنگام ضبط داخلی، بلندگو خودکار روشن شود تا صدای طرف مقابل هم ضبط شود.
  final bool autoSpeaker;

  /// ضبط‌های تازه خودکار به صف تبدیل به متن بروند.
  final bool autoTranscribe;

  final TranscriptionProvider provider;
  final String sttBaseUrl;
  final String sttModel;
  final String language;

  final bool uploadEnabled;
  final String uploadUrl;
  final bool uploadIncludeAudio;

  /// آخرین اسکن موفق پوشه‌ها (میلی‌ثانیه).
  final int lastScanAtMillis;

  /// در اولین اسکن، ضبط‌های چند روز اخیر وارد شود.
  final int importDays;

  bool get consentAccepted => consentAcceptedAt != null;
  bool get canTranscribe => provider == TranscriptionProvider.openAiCompatible;

  /// ارسال به سرور روشن است و آدرسش معتبر است (وگرنه صف بی‌هدف می‌چرخید).
  bool get uploadConfigured {
    if (!uploadEnabled) return false;
    final uri = Uri.tryParse(uploadUrl.trim());
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  bool get hasAnyOutput => canTranscribe || uploadConfigured;

  CallSettings copyWith({
    DateTime? consentAcceptedAt,
    bool? setupCompleted,
    bool? watchPhoneRecorder,
    bool? inAppRecorderEnabled,
    bool? autoSpeaker,
    bool? autoTranscribe,
    TranscriptionProvider? provider,
    String? sttBaseUrl,
    String? sttModel,
    String? language,
    bool? uploadEnabled,
    String? uploadUrl,
    bool? uploadIncludeAudio,
    int? lastScanAtMillis,
    int? importDays,
  }) {
    return CallSettings(
      consentAcceptedAt: consentAcceptedAt ?? this.consentAcceptedAt,
      setupCompleted: setupCompleted ?? this.setupCompleted,
      watchPhoneRecorder: watchPhoneRecorder ?? this.watchPhoneRecorder,
      inAppRecorderEnabled: inAppRecorderEnabled ?? this.inAppRecorderEnabled,
      autoSpeaker: autoSpeaker ?? this.autoSpeaker,
      autoTranscribe: autoTranscribe ?? this.autoTranscribe,
      provider: provider ?? this.provider,
      sttBaseUrl: sttBaseUrl ?? this.sttBaseUrl,
      sttModel: sttModel ?? this.sttModel,
      language: language ?? this.language,
      uploadEnabled: uploadEnabled ?? this.uploadEnabled,
      uploadUrl: uploadUrl ?? this.uploadUrl,
      uploadIncludeAudio: uploadIncludeAudio ?? this.uploadIncludeAudio,
      lastScanAtMillis: lastScanAtMillis ?? this.lastScanAtMillis,
      importDays: importDays ?? this.importDays,
    );
  }

  Map<String, dynamic> toJson() => {
    if (consentAcceptedAt != null)
      'consentAcceptedAt': consentAcceptedAt!.millisecondsSinceEpoch,
    'setupCompleted': setupCompleted,
    'watchPhoneRecorder': watchPhoneRecorder,
    'inAppRecorderEnabled': inAppRecorderEnabled,
    'autoSpeaker': autoSpeaker,
    'autoTranscribe': autoTranscribe,
    'provider': provider.name,
    'sttBaseUrl': sttBaseUrl,
    'sttModel': sttModel,
    'language': language,
    'uploadEnabled': uploadEnabled,
    'uploadUrl': uploadUrl,
    'uploadIncludeAudio': uploadIncludeAudio,
    'lastScanAtMillis': lastScanAtMillis,
    'importDays': importDays,
  };

  factory CallSettings.fromJson(Map<String, dynamic> json) {
    const d = CallSettings();
    String text(String key, String fallback) {
      final value = json[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : fallback;
    }

    bool flag(String key, bool fallback) {
      final value = json[key];
      return value is bool ? value : fallback;
    }

    final consent = json['consentAcceptedAt'];
    return CallSettings(
      consentAcceptedAt: consent is num && consent > 0
          ? DateTime.fromMillisecondsSinceEpoch(consent.toInt())
          : null,
      setupCompleted: flag('setupCompleted', d.setupCompleted),
      watchPhoneRecorder: flag('watchPhoneRecorder', d.watchPhoneRecorder),
      inAppRecorderEnabled: flag('inAppRecorderEnabled', d.inAppRecorderEnabled),
      autoSpeaker: flag('autoSpeaker', d.autoSpeaker),
      autoTranscribe: flag('autoTranscribe', d.autoTranscribe),
      provider: TranscriptionProvider.values.firstWhere(
        (value) => value.name == json['provider'],
        orElse: () => d.provider,
      ),
      sttBaseUrl: text('sttBaseUrl', d.sttBaseUrl),
      sttModel: text('sttModel', d.sttModel),
      language: json['language'] is String
          ? (json['language'] as String).trim()
          : d.language,
      uploadEnabled: flag('uploadEnabled', d.uploadEnabled),
      uploadUrl: json['uploadUrl'] is String
          ? (json['uploadUrl'] as String).trim()
          : d.uploadUrl,
      uploadIncludeAudio: flag('uploadIncludeAudio', d.uploadIncludeAudio),
      lastScanAtMillis: (json['lastScanAtMillis'] as num?)?.toInt() ?? 0,
      importDays: ((json['importDays'] as num?)?.toInt() ?? d.importDays).clamp(
        1,
        90,
      ),
    );
  }
}

class CallSettingsStorage {
  static Future<File> _file() async =>
      File('${await AppDir.path()}/sms_gateway_call_settings.json');

  static Future<CallSettings> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const CallSettings();
      final content = await file.readAsString();
      if (content.trim().isEmpty) return const CallSettings();
      return CallSettings.fromJson(
        Map<String, dynamic>.from(jsonDecode(content) as Map),
      );
    } catch (_) {
      return const CallSettings();
    }
  }

  static Future<void> save(CallSettings settings) async {
    await writeAtomicFile(await _file(), jsonEncode(settings.toJson()));
  }

  /// فقط یک فیلد را در فایل به‌روز می‌کند (برای اسکنر سرویس، تا تنظیمات رابط را زیر پا نگذارد).
  static Future<void> update(CallSettings Function(CallSettings) change) async {
    final mutex = FileMutex('${await AppDir.path()}/sms_gateway_call_settings.lock');
    await mutex.synchronized(() async {
      await save(change(await load()));
    });
  }
}

/// کلید API و توکن؛ فقط در حافظه‌ی رمزشده‌ی اندروید.
class CallSecrets {
  static const String _sttKey = 'stt_api_key';
  static const String _uploadToken = 'upload_token';

  static Future<String> readSttKey() => SmsBridge.secureRead(_sttKey);
  static Future<String> readUploadToken() => SmsBridge.secureRead(_uploadToken);

  static Future<void> saveSttKey(String value) => value.trim().isEmpty
      ? SmsBridge.secureDelete(_sttKey)
      : SmsBridge.secureWrite(_sttKey, value.trim());

  static Future<void> saveUploadToken(String value) => value.trim().isEmpty
      ? SmsBridge.secureDelete(_uploadToken)
      : SmsBridge.secureWrite(_uploadToken, value.trim());
}
