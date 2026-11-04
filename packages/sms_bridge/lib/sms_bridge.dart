import 'dart:async';

import 'package:flutter/services.dart';

int _i(dynamic v, int d) => v is num ? v.toInt() : d;
bool _b(dynamic v, bool d) => v is bool ? v : d;
String _s(dynamic v) => v == null ? '' : v.toString();

/// یک سیم‌کارت فعال روی گوشی
class SimCard {
  final int subscriptionId;
  final int slot; // از 0 شروع می‌شود
  final String name;
  final String carrier;
  final String number;
  final String country;
  final bool embedded;

  const SimCard({
    required this.subscriptionId,
    required this.slot,
    required this.name,
    required this.carrier,
    required this.number,
    required this.country,
    required this.embedded,
  });

  factory SimCard.fromMap(Map<String, dynamic> m) => SimCard(
        subscriptionId: _i(m['subId'], -1),
        slot: _i(m['slot'], -1),
        name: _s(m['name']),
        carrier: _s(m['carrier']),
        number: _s(m['number']),
        country: _s(m['country']),
        embedded: _b(m['embedded'], false),
      );

  String get slotLabel => 'SIM ${slot + 1}';

  String get title {
    final n = carrier.trim().isNotEmpty ? carrier.trim() : name.trim();
    return n.isEmpty ? slotLabel : '$slotLabel · $n';
  }
}

class SimQuery {
  final bool permissionGranted;
  final List<SimCard> sims;
  final int defaultSmsSubId;

  const SimQuery({
    required this.permissionGranted,
    required this.sims,
    required this.defaultSmsSubId,
  });

  static const SimQuery empty =
      SimQuery(permissionGranted: false, sims: [], defaultSmsSubId: -1);
}

/// نتیجه ارسال پیامک. code == 0 یعنی موفق؛ مقادیر مثبت کدهای SmsManager.RESULT_*
/// و مقادیر منفی کدهای داخلی این افزونه هستند:
/// -100 timeout · -101 سیم‌کارت فعال نیست · -102 استثنا · -103 مجوز ندارد
/// -104 قابلیت تلفن ندارد · -105 ورودی خالی · -106 افزونه بومی پیدا نشد
class SmsSendResult {
  final bool ok;
  final int code;
  final int parts;
  final int partsOk;
  final int subId;
  final int usedSubId;
  final int modemCode;
  final String error;

  const SmsSendResult({
    required this.ok,
    required this.code,
    required this.parts,
    required this.partsOk,
    required this.subId,
    required this.usedSubId,
    required this.modemCode,
    required this.error,
  });

  factory SmsSendResult.fromMap(Map<String, dynamic> m) => SmsSendResult(
        ok: _b(m['ok'], false),
        code: _i(m['code'], -102),
        parts: _i(m['parts'], 0),
        partsOk: _i(m['partsOk'], 0),
        subId: _i(m['subId'], -1),
        usedSubId: _i(m['usedSubId'], -1),
        modemCode: _i(m['modemCode'], -1),
        error: _s(m['error']),
      );

  factory SmsSendResult.failure(int code, String error, {int subId = -1}) =>
      SmsSendResult(
        ok: false,
        code: code,
        parts: 0,
        partsOk: 0,
        subId: subId,
        usedSubId: subId,
        modemCode: -1,
        error: error,
      );
}

/// وضعیت مجوزها و محیط دستگاه (از سمت بومی خوانده می‌شود، بدون نیاز به Activity)
class BridgeStatus {
  final bool available; // افزونه بومی در این engine ثبت شده؟
  final bool sendSms;
  final bool phoneState;
  final bool phoneNumbers;
  final bool notifications;
  final bool battery; // true = از بهینه‌سازی باتری مستثنا است
  final bool airplane;
  final bool telephony;
  final int sdk;
  final String manufacturer;
  final String model;

  /// برند گوشی با حروف کوچک (samsung، xiaomi، …) برای تشخیص ضبط‌کننده‌ی تماس.
  final String brand;

  /// آلارم دقیق (Exact alarm) مجاز است؟ در Android 12+ ممکن است کاربر بسته باشد.
  final bool exactAlarm;

  /// مجوز خواندن تاریخچه‌ی تماس.
  final bool callLog;

  /// مجوز خواندن فایل‌های صوتی (برای پیدا کردن ضبط‌های تماس).
  final bool audioMedia;

  /// مجوز میکروفون (ضبط‌کننده‌ی داخلی).
  final bool recordAudio;

  /// سرویس دسترس‌پذیری ضبط‌کننده‌ی داخلی روشن است؟
  final bool accessibility;

  const BridgeStatus({
    required this.available,
    required this.sendSms,
    required this.phoneState,
    required this.phoneNumbers,
    required this.notifications,
    required this.battery,
    required this.airplane,
    required this.telephony,
    required this.sdk,
    required this.manufacturer,
    required this.model,
    this.brand = '',
    this.exactAlarm = true,
    this.callLog = false,
    this.audioMedia = false,
    this.recordAudio = false,
    this.accessibility = false,
  });

  static const BridgeStatus unknown = BridgeStatus(
    available: false,
    sendSms: false,
    phoneState: false,
    phoneNumbers: false,
    notifications: false,
    battery: false,
    airplane: false,
    telephony: true,
    sdk: 0,
    manufacturer: '',
    model: '',
  );

  factory BridgeStatus.fromMap(Map<String, dynamic> m) => BridgeStatus(
        available: true,
        sendSms: _b(m['sendSms'], false),
        phoneState: _b(m['phoneState'], false),
        phoneNumbers: _b(m['phoneNumbers'], false),
        notifications: _b(m['notifications'], false),
        battery: _b(m['battery'], false),
        airplane: _b(m['airplane'], false),
        telephony: _b(m['telephony'], true),
        sdk: _i(m['sdk'], 0),
        manufacturer: _s(m['manufacturer']),
        model: _s(m['model']),
        brand: _s(m['brand']),
        exactAlarm: _b(m['exactAlarm'], true),
        callLog: _b(m['callLog'], false),
        audioMedia: _b(m['audioMedia'], false),
        recordAudio: _b(m['recordAudio'], false),
        accessibility: _b(m['accessibility'], false),
      );
}

class PickedContactFile {
  const PickedContactFile({required this.path, required this.name});

  final String path;
  final String name;
}

/// وضعیت آلارم بیدارکننده‌ی سرویس.
class WakeStatus {
  const WakeStatus({
    required this.canExact,
    required this.nextWakeAt,
    required this.nextWakeReason,
    required this.lastFiredAt,
    required this.lastFiredReason,
    required this.lastStartedService,
    required this.lastError,
    required this.mode,
  });

  final bool canExact;
  final DateTime? nextWakeAt;
  final String nextWakeReason;
  final DateTime? lastFiredAt;
  final String lastFiredReason;
  final bool lastStartedService;
  final String lastError;

  /// `exact`، `inexact` یا `none`
  final String mode;

  static const WakeStatus unknown = WakeStatus(
    canExact: false,
    nextWakeAt: null,
    nextWakeReason: '',
    lastFiredAt: null,
    lastFiredReason: '',
    lastStartedService: false,
    lastError: '',
    mode: 'none',
  );

  factory WakeStatus.fromMap(Map<String, dynamic> m) {
    DateTime? at(dynamic v) =>
        v is num && v > 0 ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
    return WakeStatus(
      canExact: _b(m['canExact'], false),
      nextWakeAt: at(m['nextWakeAt']),
      nextWakeReason: _s(m['nextWakeReason']),
      lastFiredAt: at(m['lastFiredAt']),
      lastFiredReason: _s(m['lastFiredReason']),
      lastStartedService: _b(m['lastStartedService'], false),
      lastError: _s(m['lastError']),
      mode: _s(m['mode']).isEmpty ? 'none' : _s(m['mode']),
    );
  }
}

/// یک ردیف خام از تاریخچه‌ی تماس گوشی.
class RawCallLogEntry {
  const RawCallLogEntry({
    required this.id,
    required this.number,
    required this.name,
    required this.startedAtMillis,
    required this.durationSeconds,
    required this.type,
  });

  final int id;
  final String number;
  final String name;
  final int startedAtMillis;
  final int durationSeconds;

  /// مقدار `CallLog.Calls.TYPE` اندروید: 1 ورودی، 2 خروجی، 3 بی‌پاسخ، 5 ردشده، 6 مسدود
  final int type;

  factory RawCallLogEntry.fromMap(Map<String, dynamic> m) => RawCallLogEntry(
    id: _i(m['id'], 0),
    number: _s(m['number']),
    name: _s(m['name']),
    startedAtMillis: _i(m['date'], 0),
    durationSeconds: _i(m['duration'], 0),
    type: _i(m['type'], 0),
  );
}

/// یک فایل صوتی پیدا شده در حافظه (MediaStore).
class RawAudioFile {
  const RawAudioFile({
    required this.id,
    required this.uri,
    required this.displayName,
    required this.relativePath,
    required this.mime,
    required this.durationMs,
    required this.sizeBytes,
    required this.dateAddedMillis,
    required this.dateModifiedMillis,
  });

  final int id;
  final String uri;
  final String displayName;
  final String relativePath;
  final String mime;
  final int durationMs;
  final int sizeBytes;
  final int dateAddedMillis;
  final int dateModifiedMillis;

  factory RawAudioFile.fromMap(Map<String, dynamic> m) => RawAudioFile(
    id: _i(m['id'], 0),
    uri: _s(m['uri']),
    displayName: _s(m['displayName']),
    relativePath: _s(m['relativePath']),
    mime: _s(m['mime']),
    durationMs: _i(m['durationMs'], 0),
    sizeBytes: _i(m['size'], 0),
    dateAddedMillis: _i(m['dateAdded'], 0),
    dateModifiedMillis: _i(m['dateModified'], 0),
  );
}

/// وضعیت ضبط‌کننده‌ی داخلی (سرویس دسترس‌پذیری).
class CallRecorderStatus {
  const CallRecorderStatus({
    required this.enabled,
    required this.autoSpeaker,
    required this.accessibilityEnabled,
    required this.recording,
    required this.lastError,
    required this.lastRecordingAt,
    required this.recordingsDir,
  });

  final bool enabled;
  final bool autoSpeaker;
  final bool accessibilityEnabled;
  final bool recording;
  final String lastError;
  final DateTime? lastRecordingAt;
  final String recordingsDir;

  static const CallRecorderStatus unknown = CallRecorderStatus(
    enabled: false,
    autoSpeaker: false,
    accessibilityEnabled: false,
    recording: false,
    lastError: '',
    lastRecordingAt: null,
    recordingsDir: '',
  );

  factory CallRecorderStatus.fromMap(Map<String, dynamic> m) {
    final at = m['lastRecordingAt'];
    return CallRecorderStatus(
      enabled: _b(m['enabled'], false),
      autoSpeaker: _b(m['autoSpeaker'], false),
      accessibilityEnabled: _b(m['accessibilityEnabled'], false),
      recording: _b(m['recording'], false),
      lastError: _s(m['lastError']),
      lastRecordingAt: at is num && at > 0
          ? DateTime.fromMillisecondsSinceEpoch(at.toInt())
          : null,
      recordingsDir: _s(m['recordingsDir']),
    );
  }
}

/// وضعیت پخش‌کننده‌ی صوتی داخلی.
class PlayerState {
  const PlayerState({
    required this.playing,
    required this.positionMs,
    required this.durationMs,
    required this.path,
  });

  final bool playing;
  final int positionMs;
  final int durationMs;
  final String path;

  static const PlayerState idle = PlayerState(
    playing: false,
    positionMs: 0,
    durationMs: 0,
    path: '',
  );

  factory PlayerState.fromMap(Map<String, dynamic> m) => PlayerState(
    playing: _b(m['playing'], false),
    positionMs: _i(m['positionMs'], 0),
    durationMs: _i(m['durationMs'], 0),
    path: _s(m['path']),
  );
}

class SmsBridge {
  SmsBridge._();

  static const MethodChannel _ch = MethodChannel('sms_bridge');

  /// مسیر پایدار filesDir برنامه (برخلاف cache پاک نمی‌شود)
  static Future<String> filesDir() async {
    try {
      return (await _ch.invokeMethod<String>('filesDir')) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<PickedContactFile?> pickContactFile() async {
    final result = await _ch.invokeMapMethod<String, dynamic>(
      'pickContactFile',
    );
    if (result == null) return null;
    final path = _s(result['path']);
    if (path.isEmpty) return null;
    return PickedContactFile(path: path, name: _s(result['name']));
  }

  static Future<BridgeStatus> status() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('status');
      if (m == null) return BridgeStatus.unknown;
      return BridgeStatus.fromMap(m);
    } catch (_) {
      return BridgeStatus.unknown;
    }
  }

  static Future<SimQuery> getSimCards() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('getSimCards');
      if (m == null) return SimQuery.empty;
      final raw = m['sims'];
      final sims = <SimCard>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) {
            sims.add(SimCard.fromMap(Map<String, dynamic>.from(e)));
          }
        }
      }
      sims.sort((a, b) => a.slot.compareTo(b.slot));
      return SimQuery(
        permissionGranted: _b(m['permission'], false),
        sims: sims,
        defaultSmsSubId: _i(m['defaultSmsSubId'], -1),
      );
    } catch (_) {
      return SimQuery.empty;
    }
  }

  /// subId < 0 یعنی سیم‌کارت پیش‌فرض پیامک گوشی.
  /// این متد هرگز استثنا پرتاب نمی‌کند؛ همیشه یک [SmsSendResult] برمی‌گرداند.
  static Future<SmsSendResult> sendSms({
    required String to,
    required String message,
    int subId = -1,
  }) async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('sendSms', {
        'to': to,
        'message': message,
        'subId': subId,
      }).timeout(const Duration(seconds: 75));
      if (m == null) {
        return SmsSendResult.failure(-102, 'پاسخ خالی از لایه بومی',
            subId: subId);
      }
      return SmsSendResult.fromMap(m);
    } on TimeoutException {
      return SmsSendResult.failure(-100, 'گزارش ارسال از سیستم نرسید',
          subId: subId);
    } on MissingPluginException catch (e) {
      return SmsSendResult.failure(-106, e.toString(), subId: subId);
    } on PlatformException catch (e) {
      return SmsSendResult.failure(-102, '${e.code}: ${e.message}',
          subId: subId);
    } catch (e) {
      return SmsSendResult.failure(-102, e.toString(), subId: subId);
    }
  }

  /// قفل CPU و Wi-Fi تا سرویس پس‌زمینه در حالت خواب (Doze) متوقف نشود
  static Future<void> acquireLocks() => setLocks(cpu: true, wifi: true);

  static Future<void> releaseLocks() => setLocks(cpu: false, wifi: false);

  /// قفل‌ها را روی وضعیت دلخواه می‌گذارد. وقتی [cpu] خاموش است، قفلِ CPUِ خودِ افزونه‌ی
  /// سرویس پس‌زمینه هم آزاد می‌شود (آن افزونه خودش هیچ‌وقت آزادش نمی‌کند).
  static Future<void> setLocks({required bool cpu, required bool wifi}) async {
    try {
      await _ch.invokeMethod<bool>('setLocks', {'cpu': cpu, 'wifi': wifi});
    } catch (_) {}
  }

  // ───────────────────────── زمان‌بندی (آلارم سیستم‌عامل) ─────────────────────────

  static void Function(String reason)? _wakeHandler;
  static bool _handlerInstalled = false;

  /// وقتی آلارم به یک ایزوله‌ی زنده می‌رسد، [handler] با دلیل بیداری صدا زده می‌شود.
  static void setWakeHandler(void Function(String reason)? handler) {
    _wakeHandler = handler;
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    // به سمت بومی بگو این ایزوله کنترل‌کننده‌ی «بیدار شو» دارد (پس نیازی به بالا آوردن دوباره‌ی سرویس نیست)
    _ch.invokeMethod<bool>('registerWakeHandler').catchError((_) => null);
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'onWake') {
        final args = call.arguments;
        final reason = args is Map ? _s(args['reason']) : _s(args);
        _wakeHandler?.call(reason);
      }
      return null;
    });
  }

  /// یک آلارم بیدارکننده برای لحظه‌ی [at] ثبت می‌کند (جایگزین آلارم قبلیِ همان [slot]؛
  /// هر بخش برنامه یک slot جدا دارد: `campaign`، `calls`، `selftest`). با کشته‌شدن
  /// برنامه یا ری‌استارت گوشی هم باقی می‌ماند. نتیجه: `exact`، `inexact` یا `failed`.
  static Future<String> scheduleWake(
    DateTime at, {
    String reason = 'schedule',
    String slot = 'campaign',
  }) async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('scheduleWake', {
        'atMillis': at.millisecondsSinceEpoch,
        'reason': reason,
        'slot': slot,
      });
      return _s(m?['mode']);
    } catch (_) {
      return 'failed';
    }
  }

  static Future<void> cancelWake({String slot = 'campaign'}) async {
    try {
      await _ch.invokeMethod<bool>('cancelWake', {'slot': slot});
    } catch (_) {}
  }

  static Future<WakeStatus> wakeStatus() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('wakeStatus');
      if (m == null) return WakeStatus.unknown;
      return WakeStatus.fromMap(m);
    } catch (_) {
      return WakeStatus.unknown;
    }
  }

  /// صفحه‌ی «آلارم‌ها و یادآورها» (Android 12+) برای دادن اجازه‌ی آلارم دقیق.
  static Future<bool> openExactAlarmSettings() =>
      _boolCall('openExactAlarmSettings');

  /// تلاش برای باز کردن صفحه‌ی «شروع خودکار/Autostart» سازنده‌ی گوشی (شیائومی، هواوی، …).
  static Future<bool> openAutoStartSettings() =>
      _boolCall('openAutoStartSettings');

  /// صفحه‌ی تنظیمات دسترس‌پذیری اندروید.
  static Future<bool> openAccessibilitySettings() =>
      _boolCall('openAccessibilitySettings');

  static Future<bool> _boolCall(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    try {
      return (await _ch.invokeMethod<bool>(method, args)) ?? false;
    } catch (_) {
      return false;
    }
  }

  // ───────────────────────── تماس‌ها و ضبط ─────────────────────────

  /// تماس‌های تاریخچه‌ی گوشی از [sinceMillis] به بعد (نیاز به مجوز READ_CALL_LOG).
  static Future<List<RawCallLogEntry>> queryCallLog({
    int sinceMillis = 0,
    int limit = 300,
  }) async {
    try {
      final raw = await _ch.invokeListMethod<dynamic>('queryCallLog', {
        'sinceMillis': sinceMillis,
        'limit': limit,
      });
      return (raw ?? const [])
          .whereType<Map>()
          .map((e) => RawCallLogEntry.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// فایل‌های صوتیِ تازه‌تر از [sinceMillis] (بر پایه‌ی زمان افزودن) از MediaStore.
  static Future<List<RawAudioFile>> queryAudioFiles({
    int sinceMillis = 0,
    int limit = 500,
  }) async {
    try {
      final raw = await _ch.invokeListMethod<dynamic>('queryAudioFiles', {
        'sinceMillis': sinceMillis,
        'limit': limit,
      });
      return (raw ?? const [])
          .whereType<Map>()
          .map((e) => RawAudioFile.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// فایلی را از آدرس محتوا (content://) به مسیر داخلی برنامه کپی می‌کند.
  static Future<String?> copyUriToFile({
    required String uri,
    required String destinationPath,
  }) async {
    try {
      return await _ch.invokeMethod<String>('copyUriToFile', {
        'uri': uri,
        'destination': destinationPath,
      });
    } catch (_) {
      return null;
    }
  }

  static Future<CallRecorderStatus> callRecorderStatus() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>(
        'callRecorderStatus',
      );
      if (m == null) return CallRecorderStatus.unknown;
      return CallRecorderStatus.fromMap(m);
    } catch (_) {
      return CallRecorderStatus.unknown;
    }
  }

  /// ضبط‌کننده‌ی داخلی (سرویس دسترس‌پذیری): روشن/خاموش و بلندگوی خودکار.
  static Future<void> configureCallRecorder({
    required bool enabled,
    required bool autoSpeaker,
  }) async {
    await _boolCall('configureCallRecorder', {
      'enabled': enabled,
      'autoSpeaker': autoSpeaker,
    });
  }

  /// ضبط دستی با میکروفون (فقط وقتی برنامه روی صفحه است).
  static Future<bool> startManualRecording() =>
      _boolCall('startManualRecording');
  static Future<bool> stopManualRecording() => _boolCall('stopManualRecording');

  // ───────────────────────── ذخیره‌ی امن ─────────────────────────

  /// مقدار حساس (مثل کلید API) را با کلید Android Keystore رمز می‌کند و ذخیره می‌کند.
  static Future<bool> secureWrite(String key, String value) =>
      _boolCall('secureWrite', {'key': key, 'value': value});

  static Future<String> secureRead(String key) async {
    try {
      return (await _ch.invokeMethod<String>('secureRead', {'key': key})) ??
          '';
    } catch (_) {
      return '';
    }
  }

  static Future<bool> secureDelete(String key) =>
      _boolCall('secureDelete', {'key': key});

  // ───────────────────────── پخش و اشتراک‌گذاری ─────────────────────────

  static Future<bool> playerPlay(String path) =>
      _boolCall('playerPlay', {'path': path});
  static Future<bool> playerPause() => _boolCall('playerPause');
  static Future<bool> playerResume() => _boolCall('playerResume');
  static Future<bool> playerStop() => _boolCall('playerStop');
  static Future<bool> playerSeek(int positionMs) =>
      _boolCall('playerSeek', {'positionMs': positionMs});

  static Future<PlayerState> playerState() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('playerState');
      if (m == null) return PlayerState.idle;
      return PlayerState.fromMap(m);
    } catch (_) {
      return PlayerState.idle;
    }
  }

  static Future<bool> shareText(String text, {String subject = ''}) =>
      _boolCall('shareText', {'text': text, 'subject': subject});

  static Future<bool> shareFile(
    String path, {
    String mime = '*/*',
    String subject = '',
  }) => _boolCall('shareFile', {
    'path': path,
    'mime': mime,
    'subject': subject,
  });
}
