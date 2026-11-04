import 'dart:convert';
import 'dart:io';

import 'package:sms_and_call/core/storage/app_storage.dart';

/// تنظیمات «احتیاط در ارسال» برای کمپین‌ها و ارسال گروهی تا اپراتور سیم‌کارت را
/// مسدود نکند. پیامک‌های گیت‌وی (کد تأیید) از این محدودیت‌ها مستثنا هستند.
class SendSettings {
  const SendSettings({
    this.minDelaySeconds = 10,
    this.jitterPercent = 25,
    this.maxPerHour = 100,
    this.maxPerDay = 0,
    this.retryAttempts = 2,
    this.pauseAfterFailures = 3,
    this.pauseMinutes = 5,
  });

  /// کمترین فاصله‌ی بین دو پیامک (ثانیه). فاصله‌ی انتخابی کمپین از این کمتر نمی‌شود.
  final int minDelaySeconds;

  /// تا چند درصد به فاصله اضافه می‌شود (تصادفی) تا الگوی ارسال ماشینی نباشد.
  final int jitterPercent;

  /// سقف پیامک در هر ساعت و در هر شبانه‌روز. صفر = بدون سقف.
  final int maxPerHour;
  final int maxPerDay;

  /// چند بار دیگر یک پیامک با خطای موقت (آنتن، رادیو) دوباره امتحان شود.
  final int retryAttempts;

  /// بعد از این تعداد شکستِ پشت‌سرهم، ارسال [pauseMinutes] دقیقه می‌ایستد.
  final int pauseAfterFailures;
  final int pauseMinutes;

  static const int hardMinDelaySeconds = 3;
  static const int hardMaxDelaySeconds = 3600;

  SendSettings normalized() => SendSettings(
    minDelaySeconds: minDelaySeconds.clamp(
      hardMinDelaySeconds,
      hardMaxDelaySeconds,
    ),
    jitterPercent: jitterPercent.clamp(0, 100),
    maxPerHour: maxPerHour.clamp(0, 10000),
    maxPerDay: maxPerDay.clamp(0, 100000),
    retryAttempts: retryAttempts.clamp(0, 10),
    pauseAfterFailures: pauseAfterFailures.clamp(1, 50),
    pauseMinutes: pauseMinutes.clamp(1, 240),
  );

  factory SendSettings.fromJson(Map<String, dynamic> json) {
    const d = SendSettings();
    int read(String key, int fallback) =>
        (json[key] as num?)?.toInt() ?? fallback;
    return SendSettings(
      minDelaySeconds: read('minDelaySeconds', d.minDelaySeconds),
      jitterPercent: read('jitterPercent', d.jitterPercent),
      maxPerHour: read('maxPerHour', d.maxPerHour),
      maxPerDay: read('maxPerDay', d.maxPerDay),
      retryAttempts: read('retryAttempts', d.retryAttempts),
      pauseAfterFailures: read('pauseAfterFailures', d.pauseAfterFailures),
      pauseMinutes: read('pauseMinutes', d.pauseMinutes),
    ).normalized();
  }

  Map<String, dynamic> toJson() => {
    'minDelaySeconds': minDelaySeconds,
    'jitterPercent': jitterPercent,
    'maxPerHour': maxPerHour,
    'maxPerDay': maxPerDay,
    'retryAttempts': retryAttempts,
    'pauseAfterFailures': pauseAfterFailures,
    'pauseMinutes': pauseMinutes,
  };

  SendSettings copyWith({
    int? minDelaySeconds,
    int? jitterPercent,
    int? maxPerHour,
    int? maxPerDay,
    int? retryAttempts,
    int? pauseAfterFailures,
    int? pauseMinutes,
  }) => SendSettings(
    minDelaySeconds: minDelaySeconds ?? this.minDelaySeconds,
    jitterPercent: jitterPercent ?? this.jitterPercent,
    maxPerHour: maxPerHour ?? this.maxPerHour,
    maxPerDay: maxPerDay ?? this.maxPerDay,
    retryAttempts: retryAttempts ?? this.retryAttempts,
    pauseAfterFailures: pauseAfterFailures ?? this.pauseAfterFailures,
    pauseMinutes: pauseMinutes ?? this.pauseMinutes,
  ).normalized();
}

class SendSettingsStorage {
  static Future<File> _file() async =>
      File('${await AppDir.path()}/sms_gateway_send_settings.json');

  static Future<SendSettings> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const SendSettings();
      final content = await file.readAsString();
      if (content.trim().isEmpty) return const SendSettings();
      return SendSettings.fromJson(
        Map<String, dynamic>.from(jsonDecode(content) as Map),
      );
    } catch (_) {
      return const SendSettings();
    }
  }

  static Future<void> save(SendSettings settings) async {
    await writeAtomicFile(
      await _file(),
      jsonEncode(settings.normalized().toJson()),
    );
  }
}

/// سابقه‌ی زمان ارسال‌های اخیر برای اجرای سقف ساعتی/روزانه. در حافظه نگه داشته می‌شود
/// و با [onChanged] روی دیسک ذخیره می‌شود (تا با ری‌استارت سرویس سقف دور زده نشود).
class SendLedger {
  SendLedger([Iterable<DateTime> initial = const []])
    : _times = initial.toList()..sort();

  final List<DateTime> _times;

  /// بعد از هر تغییر صدا زده می‌شود.
  void Function(List<DateTime> times)? onChanged;

  List<DateTime> get times => List.unmodifiable(_times);

  void record(DateTime at) {
    _times.add(at);
    _prune(at);
    onChanged?.call(times);
  }

  void _prune(DateTime now) {
    final cutoff = now.subtract(const Duration(hours: 24));
    _times.removeWhere((time) => !time.isAfter(cutoff));
  }

  int countSince(DateTime now, Duration window) {
    final cutoff = now.subtract(window);
    return _times.where((time) => time.isAfter(cutoff)).length;
  }

  /// اگر سقف ساعتی یا روزانه پر باشد، مدت انتظار تا آزاد شدن یک جا؛ وگرنه null.
  Duration? waitBeforeNext(DateTime now, SendSettings settings) {
    Duration? wait;
    void check(int limit, Duration window) {
      if (limit <= 0) return;
      final cutoff = now.subtract(window);
      final inside = _times.where((time) => time.isAfter(cutoff)).toList();
      if (inside.length < limit) return;
      // جای خالی وقتی باز می‌شود که قدیمی‌ترین ارسالِ لازم از پنجره بیرون برود.
      final blocking = inside[inside.length - limit];
      final free = blocking.add(window).difference(now);
      if (wait == null || free > wait!) wait = free;
    }

    check(settings.maxPerHour, const Duration(hours: 1));
    check(settings.maxPerDay, const Duration(hours: 24));
    final result = wait;
    if (result == null || result <= Duration.zero) return null;
    return result;
  }
}

class SendLedgerStorage {
  static Future<File> _file() async =>
      File('${await AppDir.path()}/sms_gateway_send_ledger.json');

  static Future<SendLedger> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return SendLedger();
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return SendLedger();
      return SendLedger(
        raw
            .whereType<num>()
            .map((ms) => DateTime.fromMillisecondsSinceEpoch(ms.toInt())),
      );
    } catch (_) {
      return SendLedger();
    }
  }

  static Future<void> save(List<DateTime> times) async {
    try {
      await writeAtomicFile(
        await _file(),
        jsonEncode(times.map((time) => time.millisecondsSinceEpoch).toList()),
      );
    } catch (_) {}
  }
}
